# frozen_string_literal: true

module Ollama
  class Agent
    # Enforces tool dependencies before execution
    # Prevents LLM from calling tools out of order or skipping prerequisites
    class DependencyEnforcer
      def initialize(registry: nil)
        @registry = registry
      end

      # Validate all dependencies for a tool before execution
      # @param tool_name [String] Tool name
      # @param context [Hash] Execution context (state, outputs, guards, tool_calls)
      # @return [Hash] { valid: Boolean, errors: Array<String> }
      def validate(tool_name:, context: {})
        descriptor = @registry&.descriptor(tool_name)
        return { valid: true, errors: [] } unless descriptor&.dependencies

        deps = descriptor.dependencies
        errors = []

        # ① Data dependency: required_outputs
        deps["required_outputs"]&.each do |output_key|
          unless context_has_key?(context, output_key)
            errors << "Missing required output: #{output_key} (from previous tool)"
          end
        end

        # ② State dependency: required_states
        deps["required_states"]&.each do |required_state|
          current_state = context[:state] || context["state"]
          unless current_state == required_state || current_state.to_s == required_state.to_s
            errors << "Invalid state: required '#{required_state}', current '#{current_state}'"
          end
        end

        # ③ Safety dependency: required_guards
        deps["required_guards"]&.each do |guard_name|
          guards_passed = context[:guards_passed] || context["guards_passed"] || []
          unless guards_passed.include?(guard_name) || guards_passed.include?(guard_name.to_s)
            errors << "Guard not passed: #{guard_name}"
          end
        end

        # ④ Temporal dependency: forbidden_after
        deps["forbidden_after"]&.each do |forbidden_event|
          events = context[:events] || context["events"] || []
          if events.include?(forbidden_event) || events.include?(forbidden_event.to_s)
            errors << "Tool forbidden after event: #{forbidden_event}"
          end
        end

        # ② State dependency: forbidden_states
        deps["forbidden_states"]&.each do |forbidden_state|
          current_state = context[:state] || context["state"]
          if current_state == forbidden_state || current_state.to_s == forbidden_state.to_s
            errors << "Tool forbidden in state: #{forbidden_state}"
          end
        end

        # ③ Safety dependency: forbidden_callers
        deps["forbidden_callers"]&.each do |forbidden_caller|
          caller_type = context[:caller_type] || context["caller_type"] || "LLM"
          if caller_type == forbidden_caller || caller_type.to_s == forbidden_caller.to_s
            errors << "Tool forbidden for caller type: #{forbidden_caller}"
          end
        end

        # ④ Temporal dependency: max_calls_per_trade
        if deps["max_calls_per_trade"]
          tool_calls = context[:tool_calls] || context["tool_calls"] || {}
          call_count = tool_calls[tool_name] || tool_calls[tool_name.to_s] || 0
          if call_count >= deps["max_calls_per_trade"]
            errors << "Tool call limit exceeded: max #{deps["max_calls_per_trade"]} per trade, already called #{call_count} times"
          end
        end

        # ① Data dependency: required_tools (must have been called)
        deps["required_tools"]&.each do |required_tool|
          tool_calls = context[:tool_calls] || context["tool_calls"] || {}
          unless tool_calls.key?(required_tool) || tool_calls.key?(required_tool.to_s)
            errors << "Required tool not called: #{required_tool}"
          end
        end

        # ⑤ Date constraint dependency: validate date ranges based on date_mode
        if deps["date_constraints"] && deps["date_constraints"].any?
          date_errors = validate_date_constraints(deps["date_constraints"], context)
          errors.concat(date_errors)
        end

        {
          valid: errors.empty?,
          errors: errors
        }
      end

      # Resolve derived inputs from context
      # @param tool_name [String] Tool name
      # @param args [Hash] Original tool arguments (may be empty)
      # @param context [Hash] Execution context with previous tool outputs
      # @return [Hash] Resolved arguments with derived inputs filled in
      def resolve_derived_inputs(tool_name:, args: {}, context: {})
        descriptor = @registry&.descriptor(tool_name)
        return args unless descriptor&.dependencies

        deps = descriptor.dependencies
        derived = deps["derived_inputs"] || {}
        return args if derived.empty?

        resolved_args = args.dup

        derived.each do |arg_name, path|
          # Skip if already provided explicitly
          next if resolved_args.key?(arg_name.to_sym) || resolved_args.key?(arg_name.to_s)

          # Resolve from context using path (supports dot notation and array indices)
          value = dig_context(context, path)
          if value
            resolved_args[arg_name.to_sym] = value
            resolved_args[arg_name.to_s] = value # Support both symbol and string keys
          end
        end

        resolved_args
      end

      private

      # Check if context has a key (supports nested keys like "validated_trade_plan.quantity")
      def context_has_key?(context, key)
        keys = key.to_s.split(".")
        current = context

        keys.each do |k|
          return false unless current.is_a?(Hash)

          current = current[k.to_sym] || current[k.to_s]
          return false unless current
        end

        true
      end

      # Dig into context using path notation (supports dot notation and array indices)
      # Examples:
      #   "instrument.security_id" → context[:instrument][:security_id]
      #   "expiry_list[0]" → context[:expiry_list][0]
      #   "validated_trade_plan.quantity" → context[:validated_trade_plan][:quantity]
      def dig_context(context, path)
        return nil unless context.is_a?(Hash)

        # Split by dots and brackets, handling both "expiry_list[0]" and "instrument.security_id"
        parts = path.to_s.split(/\.|\[|\]/).reject(&:empty?)
        current = context

        parts.each do |part|
          return nil unless current

          # Handle array index
          if part.match?(/^\d+$/)
            return nil unless current.is_a?(Array)

            current = current[part.to_i]
          else
            # Handle hash key (try both symbol and string)
            current = current[part.to_sym] || current[part.to_s]
          end
        end

        current
      end

      # Validate date constraints based on date_mode
      # @param date_constraints [Hash] Date constraint rules by mode (LIVE, HISTORICAL)
      # @param context [Hash] Execution context with analysis_context
      # @return [Array<String>] Array of error messages
      def validate_date_constraints(date_constraints, context)
        errors = []
        require "date"

        # Extract analysis_context
        analysis_ctx = context[:analysis_context] || context["analysis_context"]
        return ["Missing analysis_context for date validation"] unless analysis_ctx

        date_mode = analysis_ctx[:date_mode] || analysis_ctx["date_mode"]
        return ["Missing date_mode in analysis_context"] unless date_mode

        from_date_str = analysis_ctx[:from_date] || analysis_ctx["from_date"]
        to_date_str = analysis_ctx[:to_date] || analysis_ctx["to_date"]

        return ["Missing from_date or to_date in analysis_context"] unless from_date_str && to_date_str

        # Parse dates
        begin
          from_date = Date.parse(from_date_str.to_s)
          to_date = Date.parse(to_date_str.to_s)
        rescue Date::Error => e
          return ["Invalid date format: #{e.message}"]
        end

        # Get constraints for this mode
        mode_constraints = date_constraints[date_mode.to_s] || date_constraints[date_mode.to_sym]
        return [] unless mode_constraints # No constraints for this mode

        today = Date.current

        # Validate LIVE mode constraints
        if date_mode.to_s == "LIVE"
          # to_date MUST be today
          errors << "LIVE mode: to_date (#{to_date_str}) must be today (#{today})" unless to_date == today

          # from_date MUST be < to_date
          unless from_date < to_date
            errors << "LIVE mode: from_date (#{from_date_str}) must be before to_date (#{to_date_str})"
          end

          # from_date MUST be a trading day
          trading_validation_from = Vyapari::TradingCalendar.validate_trading_day(from_date)
          unless trading_validation_from[:valid]
            errors << "LIVE mode: from_date (#{from_date_str}) #{trading_validation_from[:error]}"
          end

          # to_date MUST be a trading day (if not today, but today should always be checked)
          trading_validation_to = Vyapari::TradingCalendar.validate_trading_day(to_date)
          unless trading_validation_to[:valid]
            errors << "LIVE mode: to_date (#{to_date_str}) #{trading_validation_to[:error]}"
          end
        end

        # Validate HISTORICAL mode constraints
        if date_mode.to_s == "HISTORICAL"
          # from_date <= to_date
          if from_date > to_date
            errors << "HISTORICAL mode: from_date (#{from_date_str}) cannot be after to_date (#{to_date_str})"
          end

          # Both dates MUST be trading days
          trading_validation_from = Vyapari::TradingCalendar.validate_trading_day(from_date)
          unless trading_validation_from[:valid]
            errors << "HISTORICAL mode: from_date (#{from_date_str}) #{trading_validation_from[:error]}"
          end

          trading_validation_to = Vyapari::TradingCalendar.validate_trading_day(to_date)
          unless trading_validation_to[:valid]
            errors << "HISTORICAL mode: to_date (#{to_date_str}) #{trading_validation_to[:error]}"
          end
        end

        errors
      end
    end
  end
end
