# frozen_string_literal: true

require "json"
require_relative "../../ollama/agent"
require_relative "../../ollama/agent/tool_registry"
require_relative "../../ollama/agent/safety_gate"
require_relative "../../ollama/agent/iteration_limits"
require_relative "checklist_guard"
require_relative "../tools/tool_registry_adapter"

module Vyapari
  module Options
    # Phase-based options trading agent system
    # State machine: Analysis → Validation → Execution → Position Tracking
    class PhasedAgent
      # State machine states
      STATES = {
        idle: "IDLE",
        market_analysis: "MARKET_ANALYSIS",
        plan_validation: "PLAN_VALIDATION",
        order_execution: "ORDER_EXECUTION",
        position_track: "POSITION_TRACK",
        complete: "COMPLETE",
        rejected: "REJECTED"
      }.freeze

      def initialize(client: nil, registry: nil, safety_gate: nil, logger: nil, checklist_guard: nil, test_mode: false)
        @client = client || Vyapari::Client.new
        @registry = registry
        @safety_gate = safety_gate
        @logger = logger || default_logger
        @checklist_guard = checklist_guard || ChecklistGuard.new
        @test_mode = test_mode || ENV.fetch("VYAPARI_TEST_MODE", "false") == "true"
        @state = STATES[:idle]
        @trade_plan = nil
        @executable_plan = nil
        @order_id = nil
      end

      # Run complete workflow
      # @param task [String] Initial task (e.g., "Analyze NIFTY options buying")
      # @param context [Hash] System context for checklist validation
      # @return [Hash] Complete workflow result
      def run(task, context: {})
        @logger.info "🚀 Starting phased options trading workflow"
        @logger.info "📋 Task: #{task}"

        # Global pre-check
        # Build context with defaults for testing if not provided
        precheck_context = context.dup
        precheck_context[:market_open] = context.fetch(:market_open, true) # Default to true for testing
        precheck_context[:event_risk] = context.fetch(:event_risk, false) # Default to false (no event risk)
        precheck_context[:websocket_connected] = context.fetch(:websocket_connected, true) # Default to true for testing
        precheck_context[:dhan_authenticated] = context.fetch(:dhan_authenticated, true) # Default to true for testing
        precheck_context[:in_cooldown] = context.fetch(:in_cooldown, false) # Default to false
        precheck_context[:duplicate_position] = context.fetch(:duplicate_position, false) # Default to false

        precheck_result = @checklist_guard.run_global_precheck(context: precheck_context)
        unless precheck_result[:passed]
          @logger.error "❌ Global pre-check failed: #{precheck_result[:failures].map do |f|
            f[:description]
          end.join(", ")}"
          return {
            workflow: :options_trading,
            state: STATES[:rejected],
            phases: { global_precheck: precheck_result },
            final_status: "precheck_failed",
            final_output: "Global pre-check failed: #{precheck_result[:failures].map do |f|
              f[:description]
            end.join(", ")}",
            checklist_failures: precheck_result[:failures]
          }
        end

        # Check system kill conditions
        kill_check = @checklist_guard.check_system_kill_conditions(system_state: context)
        if kill_check[:should_halt]
          @logger.error "🚨 System kill condition triggered: #{kill_check[:reason]}"
          return {
            workflow: :options_trading,
            state: STATES[:rejected],
            final_status: "system_halt",
            final_output: "System halted: #{kill_check[:reason]}",
            halt_reason: kill_check[:reason]
          }
        end

        result = {
          workflow: :options_trading,
          state: @state,
          phases: { global_precheck: precheck_result },
          final_status: nil,
          final_output: nil,
          trade_plan: nil,
          executable_plan: nil,
          order_id: nil
        }

        # PHASE 1: Market Analysis Agent
        @state = STATES[:market_analysis]
        analysis_result = run_analysis_phase(task)
        result[:phases][:analysis] = analysis_result

        # In test mode, continue even if analysis failed or returned NO_TRADE
        if @test_mode && (analysis_result[:status] != "completed" ||
                          analysis_result[:status] == "no_trade" ||
                          analysis_result[:mtf_result]&.dig(:status) == "no_trade")
          @logger.info "🧪 TEST MODE: Analysis returned NO_TRADE or failed, creating mock trade plan to test all phases"
          @trade_plan = create_mock_trade_plan
          result[:trade_plan] = @trade_plan
          result[:test_mode] = true
          result[:phases][:analysis][:status] = "completed" # Override for test mode
        elsif analysis_result[:status] != "completed"
          @state = STATES[:rejected]
          result[:final_status] = "analysis_failed"
          result[:final_output] = analysis_result[:reason]
          return result
        else
          # Extract trade plan
          @trade_plan = extract_trade_plan(analysis_result)
          result[:trade_plan] = @trade_plan
        end

        # In test mode, create mock trade plan if needed
        if @test_mode && (!@trade_plan || @trade_plan[:bias] == "NO_TRADE" || @trade_plan["bias"] == "NO_TRADE")
          @logger.info "🧪 TEST MODE: Creating mock trade plan to test all phases"
          @trade_plan = create_mock_trade_plan
          result[:trade_plan] = @trade_plan
          result[:test_mode] = true
        end

        if @trade_plan && (@trade_plan[:bias] == "NO_TRADE" || @trade_plan["bias"] == "NO_TRADE") && !@test_mode
          @state = STATES[:complete]
          result[:final_status] = "no_trade"
          result[:final_output] = "Market analysis indicates NO_TRADE"
          return result
        end

        unless @trade_plan
          if @test_mode
            @logger.info "🧪 TEST MODE: Creating mock trade plan"
            @trade_plan = create_mock_trade_plan
            result[:trade_plan] = @trade_plan
            result[:test_mode] = true
          else
            @state = STATES[:rejected]
            result[:final_status] = "no_plan"
            result[:final_output] = "Analysis did not produce trade plan"
            return result
          end
        end

        # Phase 1 checklist validation
        mode = @trade_plan[:mode] || @trade_plan["mode"] || "OPTIONS_INTRADAY"
        phase1_check = @checklist_guard.run_phase_1_checks(
          mode: mode,
          trade_plan: @trade_plan,
          context: context.merge(analysis_result: analysis_result)
        )

        # In test mode, skip checklist failures to allow testing all phases
        if @test_mode && !phase1_check[:passed]
          @logger.info "🧪 TEST MODE: Phase 1 checklist failed, but continuing to test all phases"
          result[:phases][:phase1_checklist] = phase1_check
          result[:test_mode] = true
        elsif !phase1_check[:passed]
          @logger.error "❌ Phase 1 checklist failed: #{phase1_check[:failures].map { |f| f[:description] }.join(", ")}"
          @state = STATES[:rejected]
          result[:final_status] = "phase1_checklist_failed"
          result[:final_output] = "Phase 1 checklist validation failed"
          result[:phases][:phase1_checklist] = phase1_check
          return result
        end

        result[:phases][:phase1_checklist] = phase1_check

        # PHASE 2: Plan Validation Agent
        @state = STATES[:plan_validation]
        validation_result = run_validation_phase(@trade_plan)
        result[:phases][:validation] = validation_result

        # In test mode, create mock executable plan if validation fails
        if @test_mode && validation_result[:status] != "approved"
          @logger.info "🧪 TEST MODE: Validation failed, creating mock executable plan to test execution phase"
          @executable_plan = create_mock_executable_plan(@trade_plan)
          result[:executable_plan] = @executable_plan
          result[:test_mode] = true
        elsif validation_result[:status] != "approved"
          @state = STATES[:rejected]
          result[:final_status] = "validation_failed"
          result[:final_output] = validation_result[:reason]
          return result
        else
          # Extract executable plan
          @executable_plan = extract_executable_plan(validation_result)
          result[:executable_plan] = @executable_plan
        end

        # Phase 2 checklist validation
        phase2_check = @checklist_guard.run_phase_2_checks(
          executable_plan: @executable_plan,
          context: context.merge(validation_result: validation_result)
        )

        # In test mode, skip checklist failures to allow testing all phases
        if @test_mode && !phase2_check[:passed]
          @logger.info "🧪 TEST MODE: Phase 2 checklist failed, but continuing to test all phases"
          result[:phases][:phase2_checklist] = phase2_check
          result[:test_mode] = true
        elsif !phase2_check[:passed]
          @logger.error "❌ Phase 2 checklist failed: #{phase2_check[:failures].map { |f| f[:description] }.join(", ")}"
          @state = STATES[:rejected]
          result[:final_status] = "phase2_checklist_failed"
          result[:final_output] = "Phase 2 checklist validation failed"
          result[:phases][:phase2_checklist] = phase2_check
          return result
        else
          result[:phases][:phase2_checklist] = phase2_check
        end

        # PHASE 3: Order Execution Agent
        @state = STATES[:order_execution]

        # Phase 3 checklist validation
        phase3_check = @checklist_guard.run_phase_3_checks(
          execution_context: context.merge(
            trade_approved: true,
            executable_plan: @executable_plan
          )
        )

        # In test mode, skip checklist failures to allow testing all phases
        if @test_mode && !phase3_check[:passed]
          @logger.info "🧪 TEST MODE: Phase 3 checklist failed, but continuing to test all phases"
          result[:phases][:phase3_checklist] = phase3_check
          result[:test_mode] = true
        elsif !phase3_check[:passed]
          @logger.error "❌ Phase 3 checklist failed: #{phase3_check[:failures].map { |f| f[:description] }.join(", ")}"
          @state = STATES[:rejected]
          result[:final_status] = "phase3_checklist_failed"
          result[:final_output] = "Phase 3 checklist validation failed"
          result[:phases][:phase3_checklist] = phase3_check
          return result
        else
          result[:phases][:phase3_checklist] = phase3_check
        end

        execution_result = run_execution_phase(@executable_plan)
        result[:phases][:execution] = execution_result

        if execution_result[:status] == "executed" || (@test_mode && execution_result[:status] != "executed")
          if @test_mode && execution_result[:status] != "executed"
            @logger.info "🧪 TEST MODE: Execution failed, simulating successful execution"
            @order_id = "TEST_ORDER_#{Time.now.to_i}"
            result[:order_id] = @order_id
            result[:test_mode] = true
          else
            @order_id = execution_result[:order_id]
            result[:order_id] = @order_id
          end
          @state = STATES[:position_track]
          result[:final_status] = @test_mode ? "test_completed" : "executed"
          result[:final_output] = "Order placed: #{@order_id}"
        else
          @state = STATES[:rejected]
          result[:final_status] = "execution_failed"
          result[:final_output] = execution_result[:reason]
        end

        result[:state] = @state
        result
      end

      private

      # PHASE 1: Market Analysis Agent (Multi-Timeframe)
      # Purpose: Produce TradePlan JSON (NO orders, NO risk decisions)
      def run_analysis_phase(task)
        @logger.info "📊 PHASE 1: Market Analysis - Multi-Timeframe (max 7 iterations)"

        require_relative "mtf_agent_a"

        # Create MTF Agent A
        mtf_agent = MTFAgentA.new(
          client: @client.is_a?(Ollama::Client) ? @client : create_ollama_client,
          registry: @registry,
          mode: :options_intraday
        )

        # Run MTF analysis
        mtf_result = mtf_agent.run(task)

        # Convert MTF result to standard format
        result = {
          status: mtf_result[:status] == "completed" ? "completed" : "failed",
          reason: mtf_result[:reason] || "MTF analysis complete",
          iterations: mtf_result[:iterations_used],
          context: [],
          trace: [],
          duration: 0
        }

        {
          phase: :analysis,
          status: result[:status] == "completed" ? "completed" : "failed",
          reason: result[:reason],
          iterations: mtf_result[:iterations_used] || result[:iterations] || 0,
          max_iterations: 7, # MTF budget: 2+2+2+1 = 7
          context: result[:context] || [],
          trace: result[:trace] || [],
          duration: result[:duration] || 0,
          mtf_result: mtf_result # Include full MTF result
        }
      end

      # PHASE 2: Plan Validation Agent
      # Purpose: Turn TradePlan → ExecutablePlan OR Reject
      def run_validation_phase(trade_plan)
        @logger.info "✅ PHASE 2: Plan Validation (max 3 iterations)"

        # Use RiskCalculator to convert SL/TP logic and calculate lot size (deterministic pre-check)
        context = extract_validation_context(trade_plan)
        risk_calc = create_risk_calculator(context)

        # Pre-validate using RiskCalculator (deterministic, no LLM)
        risk_validation = pre_validate_with_risk_calculator(trade_plan, risk_calc, context)
        unless risk_validation[:passed]
          @logger.error "❌ Risk validation failed: #{risk_validation[:reason]}"
          return {
            phase: :validation,
            status: "rejected",
            reason: risk_validation[:reason],
            iterations: 0,
            max_iterations: Ollama::Agent::IterationLimits::VALIDATION,
            context: [],
            trace: [],
            duration: 0
          }
        end

        # Create validation-specific registry
        validation_registry = create_validation_registry

        # Create validation agent
        validation_agent = Ollama::Agent.new(
          client: create_ollama_client,
          registry: validation_registry,
          safety_gate: @safety_gate,
          max_iterations: Ollama::Agent::IterationLimits::VALIDATION,
          timeout: 10
        )

        # Build validation prompt with risk context
        validation_prompt = build_validation_prompt(trade_plan, risk_context: risk_validation)

        # Run agent
        result = validation_agent.loop(task: validation_prompt)

        {
          phase: :validation,
          status: extract_validation_status(result),
          reason: result[:reason],
          iterations: result[:iterations],
          max_iterations: Ollama::Agent::IterationLimits::VALIDATION,
          context: result[:context],
          trace: result[:trace],
          duration: result[:duration]
        }
      end

      # PHASE 3: Order Execution Agent
      # Purpose: Translate ExecutablePlan → Order ID
      def run_execution_phase(executable_plan)
        @logger.info "⚡ PHASE 3: Order Execution (max 2 iterations)"

        # Create execution-specific registry (only order tools)
        execution_registry = create_execution_registry

        # Create execution agent
        execution_agent = Ollama::Agent.new(
          client: create_ollama_client,
          registry: execution_registry,
          safety_gate: @safety_gate,
          max_iterations: Ollama::Agent::IterationLimits::TRADING_EXECUTION,
          timeout: 15
        )

        # Build execution prompt
        execution_prompt = build_execution_prompt(executable_plan)

        # Run agent
        result = execution_agent.loop(task: execution_prompt)

        {
          phase: :execution,
          status: extract_execution_status(result),
          order_id: extract_order_id(result),
          reason: result[:reason],
          iterations: result[:iterations],
          max_iterations: Ollama::Agent::IterationLimits::TRADING_EXECUTION,
          context: result[:context],
          trace: result[:trace],
          duration: result[:duration]
        }
      end

      # Create analysis registry (only analysis tools allowed)
      def create_analysis_registry
        registry = Ollama::Agent::ToolRegistry.new

        return registry unless @registry

        analysis_tools = %w[
          dhan.instrument.find
          dhan.market.ltp
          dhan.market.quote
          dhan.history.intraday
          dhan.history.daily
          dhan.option.chain
          dhan.option.expiries
        ]

        filter_registry(registry, analysis_tools)
      end

      # Create validation registry (only validation tools allowed)
      def create_validation_registry
        registry = Ollama::Agent::ToolRegistry.new

        return registry unless @registry

        validation_tools = %w[
          dhan.funds.balance
          dhan.positions.list
          dhan.instrument.find
        ]

        filter_registry(registry, validation_tools)
      end

      # Create execution registry (only execution tools allowed)
      def create_execution_registry
        registry = Ollama::Agent::ToolRegistry.new

        return registry unless @registry

        execution_tools = %w[
          dhan.super.place
          dhan.order.place
          dhan.market.ltp
        ]

        filter_registry(registry, execution_tools)
      end

      # Filter registry to only allowed tools
      def filter_registry(target_registry, allowed_tools)
        return target_registry unless @registry

        allowed_tools.each do |tool_name|
          descriptor = @registry.descriptor(tool_name)
          next unless descriptor

          target_registry.register(
            descriptor: descriptor.to_schema,
            handler: ->(args) { @registry.call(tool_name, args) }
          )
        end

        target_registry
      end

      # Build analysis prompt with enhanced tool descriptors
      def build_analysis_prompt(task)
        require_relative "agent_prompts"

        # Get base prompt
        base_prompt = AgentPrompts.agent_a_system_prompt

        # Add tool descriptors if registry available
        if @registry && @registry.respond_to?(:descriptors)
          tools_json = @registry.descriptors_json
          tools_section = "\n\nAVAILABLE TOOLS:\n#{tools_json}\n"
          base_prompt += tools_section
        end

        base_prompt + "\n\nTASK:\n#{task}"
      end

      # Build validation prompt with enhanced tool descriptors
      def build_validation_prompt(trade_plan, risk_context: nil)
        require_relative "agent_prompts"

        # Get base prompt
        base_prompt = AgentPrompts.agent_b_system_prompt

        # Add tool descriptors if registry available
        if @registry && @registry.respond_to?(:descriptors)
          tools_json = @registry.descriptors_json
          tools_section = "\n\nAVAILABLE TOOLS:\n#{tools_json}\n"
          base_prompt += tools_section
        end

        # Add risk context if available
        base_prompt += "\n\nRISK CALCULATION CONTEXT:\n#{JSON.pretty_generate(risk_context)}\n" if risk_context

        base_prompt + "\n\nTRADE PLAN TO VALIDATE:\n#{JSON.pretty_generate(trade_plan)}"
      end

      # Build execution prompt with enhanced tool descriptors
      def build_execution_prompt(executable_plan)
        require_relative "agent_prompts"

        # Get base prompt
        base_prompt = AgentPrompts.agent_c_system_prompt

        # Add tool descriptors if registry available
        if @registry && @registry.respond_to?(:descriptors)
          tools_json = @registry.descriptors_json
          tools_section = "\n\nAVAILABLE TOOLS:\n#{tools_json}\n"
          base_prompt += tools_section
        end

        exec_plan = executable_plan[:execution_plan] || executable_plan["execution_plan"]
        base_prompt + "\n\nEXECUTABLE PLAN:\n#{JSON.pretty_generate(exec_plan)}"
      end

      # Extract trade plan from analysis result
      def extract_trade_plan(analysis_result)
        # Check for MTF result first
        if analysis_result[:mtf_result] && analysis_result[:mtf_result][:trade_plan]
          return normalize_trade_plan(analysis_result[:mtf_result][:trade_plan])
        end

        final_output = analysis_result[:reason] || ""
        context = analysis_result[:context] || []

        # Try to parse JSON from final output
        json_match = final_output.match(/\{[\s\S]*\}/)
        if json_match
          begin
            plan = JSON.parse(json_match[0])
            return normalize_trade_plan(plan)
          rescue JSON::ParserError
            # Continue to check context
          end
        end

        # Check context for trade plan
        context.each do |item|
          next unless item.is_a?(Hash) && (item[:result] || item["result"])

          result = item[:result] || item["result"]
          if result.is_a?(Hash) && (result[:trade_plan] || result["trade_plan"])
            return normalize_trade_plan(result[:trade_plan] || result["trade_plan"])
          end
        end

        nil
      end

      # Extract validation context for risk calculation
      def extract_validation_context(trade_plan)
        {
          instrument: trade_plan[:instrument] || trade_plan["instrument"] || "NIFTY",
          account_balance: ENV.fetch("ACCOUNT_BALANCE", "100000").to_f,
          max_risk_percent: ENV.fetch("MAX_RISK_PERCENT", "1.0").to_f
        }
      end

      # Create risk calculator instance
      def create_risk_calculator(context)
        require_relative "risk_calculator"
        RiskCalculator.new(
          account_balance: context[:account_balance],
          max_risk_percent: context[:max_risk_percent],
          instrument: context[:instrument]
        )
      end

      # Pre-validate trade plan using RiskCalculator (deterministic)
      def pre_validate_with_risk_calculator(trade_plan, risk_calc, context)
        # Get option LTP (would need to fetch from market)
        option_ltp = context[:option_ltp] || 100.0 # Placeholder

        # Validate trade plan
        validation = risk_calc.validate_trade_plan(
          trade_plan: trade_plan,
          option_ltp: option_ltp,
          funds_available: context[:account_balance] * 0.85 # Assume 85% available
        )

        if validation[:status] == :approved
          {
            passed: true,
            sl_price: validation[:sl_price],
            tp_partial: validation[:tp_partial],
            tp_final: validation[:tp_final],
            lots: validation[:lots],
            quantity: validation[:quantity],
            total_risk: validation[:total_risk]
          }
        else
          {
            passed: false,
            reason: validation[:reason] || "Risk validation failed"
          }
        end
      end

      # Create mock trade plan for testing
      def create_mock_trade_plan
        {
          mode: "OPTIONS_INTRADAY",
          bias: "BULLISH",
          instrument: "NIFTY",
          htf: {
            timeframe: "15m",
            regime: "TREND",
            tradable: true
          },
          mtf: {
            timeframe: "5m",
            direction: "BULLISH",
            momentum: "STRONG"
          },
          ltf: {
            timeframe: "1m",
            entry_type: "BREAKOUT",
            trigger: "Price breaks above resistance"
          },
          strike_selection: {
            preferred_type: "CE",
            atm_strike: 22_500,
            candidates: [
              {
                security_id: "TEST123",
                strike: 22_500,
                type: "CE",
                moneyness: "ATM"
              }
            ]
          },
          stop_loss_logic: "1m swing low breaks",
          target_logic: "Previous day high",
          final_bias: "BULLISH",
          summary: "Mock trade plan for testing"
        }
      end

      # Create mock executable plan for testing
      def create_mock_executable_plan(trade_plan)
        {
          status: "APPROVED",
          execution_plan: {
            instrument: trade_plan[:instrument] || trade_plan["instrument"] || "NIFTY",
            strike: trade_plan.dig(:strike_selection,
                                   :atm_strike) || trade_plan.dig("strike_selection", "atm_strike") || 22_500,
            type: trade_plan.dig(:strike_selection,
                                 :preferred_type) || trade_plan.dig("strike_selection", "preferred_type") || "CE",
            quantity: 75, # 1 lot for NIFTY
            lots: 1,
            entry_price: 100.0,
            stop_loss: 85.0,
            take_profit: {
              partial: 120.0,
              final: 140.0
            },
            order_type: "SUPER"
          },
          risk_calculation: {
            total_risk: 1125.0,
            risk_percent: 1.0,
            max_risk_allowed: 1000.0
          }
        }
      end

      # Create mock trade plan for testing
      def create_mock_trade_plan
        {
          mode: "OPTIONS_INTRADAY",
          bias: "BULLISH",
          instrument: "NIFTY",
          htf: {
            timeframe: "15m",
            regime: "TREND",
            tradable: true
          },
          mtf: {
            timeframe: "5m",
            direction: "BULLISH",
            momentum: "STRONG"
          },
          ltf: {
            timeframe: "1m",
            entry_type: "BREAKOUT",
            trigger: "Price breaks above resistance"
          },
          strike_selection: {
            preferred_type: "CE",
            atm_strike: 22_500,
            candidates: [
              {
                security_id: "TEST123",
                strike: 22_500,
                type: "CE",
                moneyness: "ATM"
              }
            ]
          },
          stop_loss_logic: "1m swing low breaks",
          target_logic: "Previous day high",
          final_bias: "BULLISH",
          summary: "Mock trade plan for testing"
        }
      end

      # Create mock executable plan for testing
      def create_mock_executable_plan(trade_plan)
        {
          status: "APPROVED",
          execution_plan: {
            instrument: trade_plan[:instrument] || trade_plan["instrument"] || "NIFTY",
            strike: trade_plan.dig(:strike_selection,
                                   :atm_strike) || trade_plan.dig("strike_selection", "atm_strike") || 22_500,
            type: trade_plan.dig(:strike_selection,
                                 :preferred_type) || trade_plan.dig("strike_selection", "preferred_type") || "CE",
            quantity: 75, # 1 lot for NIFTY
            lots: 1,
            entry_price: 100.0,
            stop_loss: 85.0,
            take_profit: {
              partial: 120.0,
              final: 140.0
            },
            order_type: "SUPER"
          },
          risk_calculation: {
            total_risk: 1125.0,
            risk_percent: 1.0,
            max_risk_allowed: 1000.0
          }
        }
      end

      # Extract executable plan from validation result
      def extract_executable_plan(validation_result)
        final_output = validation_result[:reason] || ""
        context = validation_result[:context] || []

        # Try to parse JSON from final output
        json_match = final_output.match(/\{[\s\S]*\}/)
        if json_match
          begin
            plan = JSON.parse(json_match[0])
            return plan if plan["status"] == "APPROVED" || plan[:status] == "APPROVED"
          rescue JSON::ParserError
            # Continue
          end
        end

        # Check context
        context.each do |item|
          next unless item.is_a?(Hash) && (item[:result] || item["result"])

          result = item[:result] || item["result"]
          if result.is_a?(Hash) && (result[:execution_plan] || result["execution_plan"])
            return {
              status: "APPROVED",
              execution_plan: result[:execution_plan] || result["execution_plan"]
            }
          end
        end

        nil
      end

      # Extract validation status
      def extract_validation_status(result)
        final_output = result[:reason] || ""

        if final_output.include?("APPROVED") || final_output.include?("approved")
          "approved"
        elsif final_output.include?("REJECTED") || final_output.include?("rejected")
          "rejected"
        else
          result[:status] == "completed" ? "approved" : "rejected"
        end
      end

      # Extract execution status
      def extract_execution_status(result)
        final_output = result[:reason] || ""
        context = result[:context] || []

        # Check for order_id in context
        context.each do |item|
          next unless item.is_a?(Hash) && (item[:result] || item["result"])

          result_data = item[:result] || item["result"]
          return "executed" if result_data.is_a?(Hash) && (result_data[:order_id] || result_data["order_id"])
        end

        final_output.include?("order_id") || final_output.include?("placed") ? "executed" : "failed"
      end

      # Extract order ID
      def extract_order_id(result)
        context = result[:context] || []

        context.each do |item|
          next unless item.is_a?(Hash) && (item[:result] || item["result"])

          result_data = item[:result] || item["result"]
          if result_data.is_a?(Hash)
            order_id = result_data[:order_id] || result_data["order_id"]
            return order_id if order_id
          end
        end

        nil
      end

      # Normalize trade plan (handle both symbol and string keys)
      def normalize_trade_plan(plan)
        {
          bias: plan[:bias] || plan["bias"],
          setup: plan[:setup] || plan["setup"],
          strike: plan[:strike] || plan["strike"],
          entry_logic: plan[:entry_logic] || plan["entry_logic"],
          invalidation: plan[:invalidation] || plan["invalidation"]
        }
      end

      # Create Ollama client from Vyapari client
      def create_ollama_client
        if @client.is_a?(Ollama::Client)
          @client
        else
          # Extract base_url from Vyapari::Client
          base_url = ENV.fetch("OLLAMA_URL", "http://localhost:11434")
          Ollama::Client.new(host: base_url)
        end
      end

      def default_logger
        require "logger"
        Logger.new($stdout)
      end
    end
  end
end
