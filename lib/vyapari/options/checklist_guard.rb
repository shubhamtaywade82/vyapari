# frozen_string_literal: true

require "yaml"
require "time"

# Phase-based checklist guard for Vyapari
# Enforces capital-safe checklist for Options Buying & Swing Long Trading

module Vyapari
  module Options
    class ChecklistGuard
      attr_reader :config, :results, :failures

      def initialize(config_path: nil)
        @config_path = config_path || File.join(__dir__, "checklist_config.yml")
        @config = load_config
        @results = {}
        @failures = []
      end

      # Run global pre-check
      # @param context [Hash] System context (market_open, websocket_connected, etc.)
      # @return [Hash] { passed: Boolean, failures: Array }
      def run_global_precheck(context: {})
        phase = @config["global_precheck"]
        results = run_checks(phase["checks"], context)

        {
          phase: "global_precheck",
          passed: results[:passed],
          failures: results[:failures],
          action: results[:passed] ? nil : "STOP_SYSTEM"
        }
      end

      # Run Phase 1 (Agent A) checks
      # @param mode [String] "OPTIONS_INTRADAY" or "SWING_LONG"
      # @param trade_plan [Hash] Trade plan from Agent A
      # @param context [Hash] Additional context
      # @return [Hash] { passed: Boolean, failures: Array, action: String }
      def run_phase_1_checks(mode:, trade_plan:, context: {})
        phase_config = @config["phase_1_agent_a"]

        # Mode selection check
        unless phase_config["mode_selection"]["allowed_modes"].include?(mode)
          return {
            phase: "phase_1",
            passed: false,
            failures: ["Invalid mode: #{mode}"],
            action: "STOP"
          }
        end

        # Run mode-specific checks
        mode_key = mode.downcase.gsub("_", "_")
        mode_config = phase_config[mode_key]

        unless mode_config
          return {
            phase: "phase_1",
            passed: false,
            failures: ["No configuration for mode: #{mode}"],
            action: "STOP"
          }
        end

        all_results = {}
        all_failures = []

        # Run timeframe checks
        mode_config.each do |timeframe_key, timeframe_config|
          next unless timeframe_config.is_a?(Hash) && timeframe_config["checks"]

          timeframe_results = run_checks(timeframe_config["checks"], trade_plan.merge(context))
          all_results[timeframe_key] = timeframe_results
          all_failures.concat(timeframe_results[:failures]) if timeframe_results[:failures]
        end

        # Check required outputs
        if mode_config["required_outputs"]
          missing_outputs = mode_config["required_outputs"].reject { |output| trade_plan.key?(output.to_sym) || trade_plan.key?(output) }
          if missing_outputs.any?
            all_failures << "Missing required outputs: #{missing_outputs.join(', ')}"
          end
        end

        passed = all_failures.empty?

        {
          phase: "phase_1",
          passed: passed,
          failures: all_failures,
          action: passed ? nil : "NO_TRADE",
          results: all_results
        }
      end

      # Run Phase 2 (Agent B) checks
      # @param executable_plan [Hash] Executable plan from Agent B
      # @param context [Hash] Additional context (funds, lot_size, etc.)
      # @return [Hash] { passed: Boolean, failures: Array, action: String }
      def run_phase_2_checks(executable_plan:, context: {})
        phase_config = @config["phase_2_agent_b"]
        all_failures = []

        # Capital & Risk Check
        capital_results = run_checks(phase_config["capital_risk_check"]["checks"], context)
        all_failures.concat(capital_results[:failures]) if capital_results[:failures]

        # Stop-Loss Validation
        sl_config = phase_config["stop_loss_validation"]
        sl_results = validate_stop_loss(executable_plan, sl_config, context)
        all_failures.concat(sl_results[:failures]) if sl_results[:failures]

        # Lot Size Calculation
        lot_config = phase_config["lot_size_calculation"]
        lot_results = validate_lot_size(executable_plan, lot_config, context)
        all_failures.concat(lot_results[:failures]) if lot_results[:failures]

        # Take Profit Validation
        tp_results = validate_take_profit(executable_plan, phase_config["take_profit_validation"], context)
        all_failures.concat(tp_results[:failures]) if tp_results[:failures]

        # Executable Plan Validation
        plan_results = validate_executable_plan(executable_plan, phase_config["executable_plan"])
        all_failures.concat(plan_results[:failures]) if plan_results[:failures]

        passed = all_failures.empty?

        {
          phase: "phase_2",
          passed: passed,
          failures: all_failures,
          action: passed ? nil : "REJECT",
          results: {
            capital: capital_results,
            stop_loss: sl_results,
            lot_size: lot_results,
            take_profit: tp_results,
            plan: plan_results
          }
        }
      end

      # Run Phase 3 (Agent C) checks
      # @param execution_context [Hash] Execution context
      # @return [Hash] { passed: Boolean, failures: Array, action: String }
      def run_phase_3_checks(execution_context: {})
        phase_config = @config["phase_3_agent_c"]
        results = run_checks(phase_config["pre_execution"]["checks"], execution_context)

        {
          phase: "phase_3",
          passed: results[:passed],
          failures: results[:failures],
          action: results[:passed] ? nil : "STOP_AND_ALERT"
        }
      end

      # Run Phase 4 (Position Tracking) checks
      # @param position_context [Hash] Position context
      # @return [Hash] { passed: Boolean, failures: Array }
      def run_phase_4_checks(position_context: {})
        phase_config = @config["phase_4_position_tracking"]

        init_results = run_checks(phase_config["initialization"]["checks"], position_context)
        live_results = run_checks(phase_config["live_management"]["checks"], position_context)

        all_failures = []
        all_failures.concat(init_results[:failures]) if init_results[:failures]
        all_failures.concat(live_results[:failures]) if live_results[:failures]

        {
          phase: "phase_4",
          passed: all_failures.empty?,
          failures: all_failures,
          results: {
            initialization: init_results,
            live_management: live_results
          }
        }
      end

      # Check hard system kill conditions
      # @param system_state [Hash] Current system state
      # @return [Hash] { should_halt: Boolean, reason: String }
      def check_system_kill_conditions(system_state: {})
        conditions = @config["hard_system_kill_conditions"]["conditions"]

        conditions.each do |condition|
          check_id = condition["id"]
          check_method = "check_#{check_id}"

          if respond_to?(check_method, true)
            result = send(check_method, system_state)
            return { should_halt: true, reason: condition["description"], action: condition["action"] } if result
          end
        end

        { should_halt: false }
      end

      private

      def load_config
        YAML.safe_load(File.read(@config_path))
      end

      def run_checks(checks, context)
        failures = []

        checks.each do |check|
          check_id = check["id"]
          required = check["required"] != false

          # Check if condition is met
          passed = evaluate_check(check, context)

          unless passed
            if required
              failures << {
                check_id: check_id,
                description: check["description"],
                required: required,
                rejection_action: check["rejection_action"]
              }
            end
          end
        end

        {
          passed: failures.empty?,
          failures: failures
        }
      end

      def evaluate_check(check, context)
        check_id = check["id"]

        # Custom evaluation logic based on check ID
        case check_id
        when "market_open"
          context[:market_open] != false
        when "websocket_connected"
          context[:websocket_connected] == true
        when "dhan_authenticated"
          context[:dhan_authenticated] == true
        when "not_in_cooldown"
          context[:in_cooldown] != true
        when "no_duplicate_position"
          context[:duplicate_position] != true
        when "regime_classified"
          regime = context[:regime] || context["regime"]
          allowed = check["required_regime"] || []
          allowed.include?(regime)
        when "direction_decided"
          direction = context[:direction] || context["direction"]
          allowed = check["allowed_values"] || []
          allowed.include?(direction)
        when "alignment_with_htf"
          context[:alignment_with_htf] != false
        else
          # Default: check if context has the key and it's truthy
          context.key?(check_id.to_sym) || context.key?(check_id)
        end
      end

      def validate_stop_loss(executable_plan, sl_config, context)
        failures = []

        sl_price = executable_plan[:stop_loss] || executable_plan["stop_loss"]
        entry_price = executable_plan[:entry_price] || executable_plan["entry_price"]
        instrument = context[:instrument] || "NIFTY"

        unless sl_price && entry_price
          failures << { check_id: "sl_converted_to_numeric", description: "SL or entry price missing" }
          return { passed: false, failures: failures }
        end

        # Calculate SL percentage
        sl_percent = ((entry_price - sl_price).abs / entry_price) * 100

        # Check against caps
        max_sl = sl_config["max_sl_percentages"][instrument] || 30
        if sl_percent > max_sl
          failures << {
            check_id: "sl_within_caps",
            description: "SL percentage (#{sl_percent.round(2)}%) exceeds max (#{max_sl}%)"
          }
        end

        {
          passed: failures.empty?,
          failures: failures,
          sl_percent: sl_percent
        }
      end

      def validate_lot_size(executable_plan, lot_config, context)
        failures = []

        lots = executable_plan[:lots] || executable_plan["lots"]
        quantity = executable_plan[:quantity] || executable_plan["quantity"]
        instrument = context[:instrument] || "NIFTY"
        lot_size = context[:lot_size] || @config.dig("phase_2_agent_b", "capital_risk_check", "checks", 2, "lot_sizes", instrument) || 75

        unless lots && lots >= 1
          failures << {
            check_id: "min_lots_met",
            description: "Lots must be >= 1, got: #{lots}"
          }
        end

        max_lots = lot_config["max_lots"] || 6
        if lots && lots > max_lots
          failures << {
            check_id: "max_lots_capped",
            description: "Lots (#{lots}) exceeds max (#{max_lots})"
          }
        end

        # Verify quantity = lots × lot_size
        expected_quantity = lots * lot_size if lots
        if expected_quantity && quantity != expected_quantity
          failures << {
            check_id: "quantity_matches_lots",
            description: "Quantity (#{quantity}) does not match lots × lot_size (#{expected_quantity})"
          }
        end

        {
          passed: failures.empty?,
          failures: failures
        }
      end

      def validate_take_profit(executable_plan, tp_config, context)
        failures = []

        tp = executable_plan[:take_profit] || executable_plan["take_profit"]
        entry_price = executable_plan[:entry_price] || executable_plan["entry_price"]
        stop_loss = executable_plan[:stop_loss] || executable_plan["stop_loss"]

        unless tp && entry_price && stop_loss
          failures << { check_id: "take_profit_defined", description: "Take profit, entry, or SL missing" }
          return { passed: false, failures: failures }
        end

        # Calculate risk
        risk = (entry_price - stop_loss).abs

        # Check partial TP
        if tp[:partial] || tp["partial"]
          partial = tp[:partial] || tp["partial"]
          partial_price = partial[:price] || partial["price"]
          partial_rr = partial[:rr] || partial["rr"]

          if partial_price
            calculated_rr = (partial_price - entry_price) / risk
            min_rr = tp_config["min_rr"] || 1.5

            if calculated_rr < min_rr
              failures << {
                check_id: "min_rr_met",
                description: "Partial TP RR (#{calculated_rr.round(2)}x) below minimum (#{min_rr}x)"
              }
            end
          end
        end

        {
          passed: failures.empty?,
          failures: failures
        }
      end

      def validate_executable_plan(executable_plan, plan_config)
        failures = []
        required_fields = plan_config["required_fields"] || []

        required_fields.each do |field|
          unless executable_plan.key?(field.to_sym) || executable_plan.key?(field)
            failures << {
              check_id: "required_field_#{field}",
              description: "Required field missing: #{field}"
            }
          end
        end

        {
          passed: failures.empty?,
          failures: failures
        }
      end

      # Hard system kill condition checkers
      def check_max_daily_loss_breached(system_state)
        daily_loss = system_state[:daily_loss] || system_state["daily_loss"]
        max_daily_loss = system_state[:max_daily_loss] || system_state["max_daily_loss"]
        daily_loss && max_daily_loss && daily_loss >= max_daily_loss
      end

      def check_ws_disconnected_mid_position(system_state)
        ws_connected = system_state[:websocket_connected] || system_state["websocket_connected"]
        has_position = system_state[:has_position] || system_state["has_position"]
        has_position && !ws_connected
      end

      def check_duplicate_execution_detected(system_state)
        system_state[:duplicate_execution] == true || system_state["duplicate_execution"] == true
      end

      def check_invalid_state_transition(system_state)
        system_state[:invalid_transition] == true || system_state["invalid_transition"] == true
      end

      def check_unexpected_llm_output(system_state)
        system_state[:unexpected_llm_output] == true || system_state["unexpected_llm_output"] == true
      end
    end
  end
end

