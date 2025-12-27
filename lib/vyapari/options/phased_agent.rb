# frozen_string_literal: true

require "json"
require_relative "../../ollama/agent"
require_relative "../../ollama/agent/tool_registry"
require_relative "../../ollama/agent/safety_gate"
require_relative "../../ollama/agent/iteration_limits"

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

      def initialize(client: nil, registry: nil, safety_gate: nil, logger: nil)
        @client = client || Vyapari::Client.new
        @registry = registry
        @safety_gate = safety_gate
        @logger = logger || default_logger
        @state = STATES[:idle]
        @trade_plan = nil
        @executable_plan = nil
        @order_id = nil
      end

      # Run complete workflow
      # @param task [String] Initial task (e.g., "Analyze NIFTY options buying")
      # @return [Hash] Complete workflow result
      def run(task)
        @logger.info "🚀 Starting phased options trading workflow"
        @logger.info "📋 Task: #{task}"

        result = {
          workflow: :options_trading,
          state: @state,
          phases: {},
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

        unless analysis_result[:status] == "completed"
          @state = STATES[:rejected]
          result[:final_status] = "analysis_failed"
          result[:final_output] = analysis_result[:reason]
          return result
        end

        # Extract trade plan
        @trade_plan = extract_trade_plan(analysis_result)
        result[:trade_plan] = @trade_plan

        if @trade_plan && @trade_plan[:bias] == "NO_TRADE"
          @state = STATES[:complete]
          result[:final_status] = "no_trade"
          result[:final_output] = "Market analysis indicates NO_TRADE"
          return result
        end

        unless @trade_plan
          @state = STATES[:rejected]
          result[:final_status] = "no_plan"
          result[:final_output] = "Analysis did not produce trade plan"
          return result
        end

        # PHASE 2: Plan Validation Agent
        @state = STATES[:plan_validation]
        validation_result = run_validation_phase(@trade_plan)
        result[:phases][:validation] = validation_result

        unless validation_result[:status] == "approved"
          @state = STATES[:rejected]
          result[:final_status] = "validation_failed"
          result[:final_output] = validation_result[:reason]
          return result
        end

        # Extract executable plan
        @executable_plan = extract_executable_plan(validation_result)
        result[:executable_plan] = @executable_plan

        # PHASE 3: Order Execution Agent
        @state = STATES[:order_execution]
        execution_result = run_execution_phase(@executable_plan)
        result[:phases][:execution] = execution_result

        if execution_result[:status] == "executed"
          @order_id = execution_result[:order_id]
          result[:order_id] = @order_id
          @state = STATES[:position_track]
          result[:final_status] = "executed"
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

      # PHASE 1: Market Analysis Agent
      # Purpose: Produce TradePlan JSON (NO orders, NO risk decisions)
      def run_analysis_phase(task)
        @logger.info "📊 PHASE 1: Market Analysis (max 8 iterations)"

        # Create analysis-specific registry (only analysis tools)
        analysis_registry = create_analysis_registry

        # Create analysis agent
        analysis_agent = Ollama::Agent.new(
          client: @client.is_a?(Ollama::Client) ? @client : create_ollama_client,
          registry: analysis_registry,
          max_iterations: Ollama::Agent::IterationLimits::ANALYSIS,
          timeout: 60
        )

        # Build analysis prompt
        analysis_prompt = build_analysis_prompt(task)

        # Run agent
        result = analysis_agent.loop(task: analysis_prompt)

        {
          phase: :analysis,
          status: result[:status] == "completed" ? "completed" : "failed",
          reason: result[:reason],
          iterations: result[:iterations],
          max_iterations: Ollama::Agent::IterationLimits::ANALYSIS,
          context: result[:context],
          trace: result[:trace],
          duration: result[:duration]
        }
      end

      # PHASE 2: Plan Validation Agent
      # Purpose: Turn TradePlan → ExecutablePlan OR Reject
      def run_validation_phase(trade_plan)
        @logger.info "✅ PHASE 2: Plan Validation (max 3 iterations)"

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

        # Build validation prompt
        validation_prompt = build_validation_prompt(trade_plan)

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

      # Build analysis prompt
      def build_analysis_prompt(task)
        require_relative "agent_prompts"
        AgentPrompts.agent_a_system_prompt + "\n\nTASK:\n#{task}"
      end

      # Build validation prompt
      def build_validation_prompt(trade_plan)
        require_relative "agent_prompts"
        AgentPrompts.agent_b_system_prompt + "\n\nTRADE PLAN TO VALIDATE:\n#{JSON.pretty_generate(trade_plan)}"
      end

      # Build execution prompt
      def build_execution_prompt(executable_plan)
        require_relative "agent_prompts"
        exec_plan = executable_plan[:execution_plan] || executable_plan["execution_plan"]
        AgentPrompts.agent_c_system_prompt + "\n\nEXECUTABLE PLAN:\n#{JSON.pretty_generate(exec_plan)}"
      end

      # Extract trade plan from analysis result
      def extract_trade_plan(analysis_result)
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
