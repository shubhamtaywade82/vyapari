# frozen_string_literal: true

require_relative "agent"
require "json"

module Ollama
  class Agent
    # Phase-based multi-agent orchestrator
    # Breaks complex goals into phases, each with bounded iterations
    class PhasedAgent
      # Production-safe iteration limits per phase
      ITERATION_LIMITS = {
        analysis: 8,      # Deep reasoning allowed
        validation: 3,    # Quick checks only
        execution: 2,      # Fast execution
        planning: 4,       # Strategy planning
        monitoring: 1      # Status checks
      }.freeze

      def initialize(client: nil, registry: nil, safety_gate: nil)
        @client = client || Ollama::Client.new
        @registry = registry
        @safety_gate = safety_gate
        @phase_results = {}
      end

      # Run complete workflow through phases
      # @param workflow [Symbol] Workflow type (:options_trading, :swing_trading, etc.)
      # @param task [String] Initial task
      # @return [Hash] Complete workflow result
      def run(workflow:, task:)
        case workflow
        when :options_trading
          run_options_workflow(task)
        when :swing_trading
          run_swing_workflow(task)
        else
          { error: "Unknown workflow: #{workflow}" }
        end
      end

      private

      # Options trading workflow: Analysis → Validation → Execution
      def run_options_workflow(task)
        result = {
          workflow: :options_trading,
          phases: {},
          final_status: nil,
          final_output: nil
        }

        # PHASE 1: Analysis Agent
        analysis_result = run_phase(
          phase: :analysis,
          task: build_analysis_task(task),
          allowed_tools: analysis_tools,
          max_iterations: ITERATION_LIMITS[:analysis]
        )
        result[:phases][:analysis] = analysis_result

        # Early exit if analysis fails
        unless analysis_result[:status] == "completed"
          result[:final_status] = "analysis_failed"
          result[:final_output] = analysis_result[:reason]
          return result
        end

        # Extract trade plan from analysis
        trade_plan = extract_trade_plan(analysis_result)
        return result.merge(final_status: "no_trade", final_output: "Analysis did not produce trade plan") unless trade_plan

        # PHASE 2: Validation Agent
        validation_result = run_phase(
          phase: :validation,
          task: build_validation_task(trade_plan),
          allowed_tools: validation_tools,
          max_iterations: ITERATION_LIMITS[:validation]
        )
        result[:phases][:validation] = validation_result

        # Early exit if validation fails
        unless validation_result[:status] == "approved"
          result[:final_status] = "validation_failed"
          result[:final_output] = validation_result[:reason]
          return result
        end

        # PHASE 3: Execution Agent (only if approved)
        if validation_result[:status] == "approved"
          execution_result = run_phase(
            phase: :execution,
            task: build_execution_task(trade_plan),
            allowed_tools: execution_tools,
            max_iterations: ITERATION_LIMITS[:execution]
          )
          result[:phases][:execution] = execution_result
          result[:final_status] = execution_result[:status]
          result[:final_output] = execution_result[:reason]
        end

        result
      end

      # Swing trading workflow
      def run_swing_workflow(task)
        # Similar structure but different tools/phases
        result = {
          workflow: :swing_trading,
          phases: {},
          final_status: nil,
          final_output: nil
        }

        # PHASE 1: Analysis
        analysis_result = run_phase(
          phase: :analysis,
          task: build_swing_analysis_task(task),
          allowed_tools: swing_analysis_tools,
          max_iterations: ITERATION_LIMITS[:analysis]
        )
        result[:phases][:analysis] = analysis_result
        result[:final_status] = analysis_result[:status]
        result[:final_output] = analysis_result[:reason]

        result
      end

      # Run a single phase with bounded iterations
      # @param phase [Symbol] Phase name
      # @param task [String] Phase-specific task
      # @param allowed_tools [Array<String>] Tools allowed in this phase
      # @param max_iterations [Integer] Max iterations for this phase
      # @return [Hash] Phase result
      def run_phase(phase:, task:, allowed_tools:, max_iterations:)
        # Create phase-specific registry (filter tools)
        phase_registry = create_phase_registry(allowed_tools)

        # Create phase-specific agent
        phase_agent = Ollama::Agent.new(
          client: @client,
          registry: phase_registry,
          safety_gate: @safety_gate,
          max_iterations: max_iterations,
          timeout: phase_timeout(phase)
        )

        # Build phase-specific system prompt
        system_prompt = build_phase_prompt(phase, allowed_tools)

        # Run agent loop
        result = phase_agent.loop(
          task: "#{system_prompt}\n\nTASK: #{task}"
        )

        # Format phase result
        {
          phase: phase,
          status: result[:status],
          reason: result[:reason],
          iterations: result[:iterations],
          max_iterations: max_iterations,
          context: result[:context],
          trace: result[:trace],
          duration: result[:duration]
        }
      end

      # Create filtered registry for phase
      def create_phase_registry(allowed_tools)
        return @registry unless @registry && allowed_tools.any?

        # Create new registry with only allowed tools
        filtered_registry = ToolRegistry.new

        @registry.tool_names.each do |tool_name|
          if allowed_tools.include?(tool_name)
            descriptor = @registry.descriptor(tool_name)
            # Get handler from original registry (would need to expose this)
            # For now, just copy the descriptor
            filtered_registry.register(
              descriptor: descriptor.to_schema,
              handler: ->(args) { @registry.call(tool_name, args) }
            )
          end
        end

        filtered_registry
      end

      # Build phase-specific system prompt
      def build_phase_prompt(phase, allowed_tools)
        case phase
        when :analysis
          <<~PROMPT
            You are an ANALYSIS agent for options trading.

            YOUR ROLE:
            - Analyze market data, historical patterns, and option chains
            - Generate a trade plan with entry, stop-loss, and target
            - DO NOT place any orders
            - Output final plan as JSON

            ALLOWED TOOLS: #{allowed_tools.join(", ")}

            RULES:
            - Use tools to gather data
            - Analyze and produce trade plan
            - Output plan when complete (action: "final")
            - Maximum #{ITERATION_LIMITS[:analysis]} iterations
          PROMPT

        when :validation
          <<~PROMPT
            You are a VALIDATION agent for options trading.

            YOUR ROLE:
            - Validate trade plan against risk rules
            - Check available funds
            - Verify stop-loss is set
            - Output APPROVED or REJECTED

            ALLOWED TOOLS: #{allowed_tools.join(", ")}

            RULES:
            - Check funds before approving
            - Verify stop-loss exists
            - Check position size limits
            - Maximum #{ITERATION_LIMITS[:validation]} iterations
            - Output "approved" or "rejected" as final action
          PROMPT

        when :execution
          <<~PROMPT
            You are an EXECUTION agent for options trading.

            YOUR ROLE:
            - Execute approved trade plan
            - Place Super Order with SL/TP
            - Confirm execution

            ALLOWED TOOLS: #{allowed_tools.join(", ")}

            RULES:
            - Execute exactly as planned
            - Place Super Order only
            - Maximum #{ITERATION_LIMITS[:execution]} iterations
            - Output order_id when complete
          PROMPT

        else
          "You are a #{phase} agent. Use tools to complete the task."
        end
      end

      # Tool lists per phase
      def analysis_tools
        %w[
          dhan.instrument.find
          dhan.market.ltp
          dhan.market.quote
          dhan.history.intraday
          dhan.history.daily
          dhan.option.chain
          dhan.option.expiries
        ]
      end

      def validation_tools
        %w[
          dhan.funds.balance
          dhan.positions.list
          dhan.market.ltp
        ]
      end

      def execution_tools
        %w[
          dhan.super.place
          dhan.order.place
          dhan.market.ltp
        ]
      end

      def swing_analysis_tools
        %w[
          dhan.instrument.find
          dhan.history.daily
          dhan.market.quote
        ]
      end

      # Build phase-specific tasks
      def build_analysis_task(original_task)
        <<~TASK
          #{original_task}

          Analyze the market and produce a trade plan with:
          - Entry price/strike
          - Stop-loss price
          - Target price
          - Quantity
          - Rationale

          Output final plan as JSON when complete.
        TASK
      end

      def build_validation_task(trade_plan)
        <<~TASK
          Validate this trade plan:

          #{JSON.pretty_generate(trade_plan)}

          Check:
          1. Available funds sufficient
          2. Stop-loss is defined
          3. Position size within limits
          4. Market conditions acceptable

          Output "approved" or "rejected" with reason.
        TASK
      end

      def build_execution_task(trade_plan)
        <<~TASK
          Execute this approved trade plan:

          #{JSON.pretty_generate(trade_plan)}

          Place Super Order with:
          - Entry: #{trade_plan[:entry_price] || trade_plan["entry_price"]}
          - Stop-loss: #{trade_plan[:stop_loss] || trade_plan["stop_loss"]}
          - Target: #{trade_plan[:target] || trade_plan["target"]}
          - Quantity: #{trade_plan[:quantity] || trade_plan["quantity"]}

          Confirm order_id when placed.
        TASK
      end

      def build_swing_analysis_task(original_task)
        "#{original_task}\n\nAnalyze for swing trading opportunities."
      end

      # Extract trade plan from analysis result
      def extract_trade_plan(analysis_result)
        # Look for trade plan in final output or context
        final_output = analysis_result[:reason] || ""
        context = analysis_result[:context] || []

        # Try to parse JSON from final output
        json_match = final_output.match(/\{[\s\S]*\}/)
        if json_match
          begin
            return JSON.parse(json_match[0])
          rescue JSON::ParserError
            # Continue to check context
          end
        end

        # Check context for trade plan
        context.each do |item|
          if item.is_a?(Hash) && (item[:result] || item["result"])
            result = item[:result] || item["result"]
            if result.is_a?(Hash) && (result[:trade_plan] || result["trade_plan"])
              return result[:trade_plan] || result["trade_plan"]
            end
          end
        end

        nil
      end

      # Phase-specific timeouts
      def phase_timeout(phase)
        case phase
        when :analysis then 60  # Allow more time for analysis
        when :validation then 10 # Quick validation
        when :execution then 15  # Fast execution
        else 30
        end
      end
    end
  end
end

