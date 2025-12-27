# frozen_string_literal: true

require "json"

module Ollama
  class Agent
    # Bounded agent loop controller
    # Enforces iteration limits, timeouts, and token budgets
    # IMPORTANT: 1 iteration = 1 LLM call + 0-1 tool execution
    class Loop
      DEFAULT_MAX_ITERATIONS = 3
      DEFAULT_TIMEOUT = 30 # seconds
      DEFAULT_MAX_TOKENS = 40_000

      def initialize(planner:, executor:, verifier:, max_iterations: DEFAULT_MAX_ITERATIONS, timeout: DEFAULT_TIMEOUT,
                     max_tokens: DEFAULT_MAX_TOKENS)
        @planner = planner
        @executor = executor
        @verifier = verifier
        @max_iterations = max_iterations
        @timeout = timeout
        @max_tokens = max_tokens
        @start_time = nil
        @token_count = 0
      end

      # Run the agent loop until completion or limits reached
      # IMPORTANT: Each iteration = 1 LLM call + 0-1 tool execution
      # @param task [String] Initial task
      # @param plan_schema [Hash] JSON schema for plans
      # @return [Hash] Final result with context and trace
      def run(task:, plan_schema:)
        @start_time = Time.now
        @token_count = 0
        context = []
        iteration = 0
        trace = []

        # Hard limit: never exceed max_iterations
        while iteration < @max_iterations
          iteration += 1

          # Check timeout
          return build_result(context, trace, "timeout", "Timeout reached") if timeout_reached?

          # Generate plan
          plan = @planner.plan(
            task: task_with_context(task, context),
            schema: plan_schema,
            context: context
          )

          trace << { iteration: iteration, plan: plan, timestamp: Time.now }

          # Verify plan
          verification = @verifier.verify_plan(plan)
          unless verification[:valid]
            return build_result(context, trace, "verification_failed", verification[:errors].join(", "))
          end

          # Check action type (new format) or legacy steps format
          action = plan["action"] || plan[:action]

          if action == "final"
            final_output = plan["final_output"] || plan[:final_output] || "Task completed"
            return build_result(context, trace, "completed", final_output)
          end

          # Handle tool_call action (new format)
          if action == "tool_call"
            tool_name = plan["tool_name"] || plan[:tool_name]
            tool_args = plan["tool_args"] || plan[:tool_args] || {}

            return build_result(context, trace, "error", "tool_call action missing tool_name") unless tool_name

            result = @executor.execute(tool_name: tool_name, args: tool_args, context: context)
            context << result
            trace << { iteration: iteration, tool_call: { tool: tool_name, args: tool_args }, result: result,
                       timestamp: Time.now }

            # For tool_call, check if result indicates error
            results = [result]

          elsif action.nil? || action.empty?
            # Legacy: support steps array format
            steps = plan["steps"] || plan[:steps] || []
            return build_result(context, trace, "completed", "No steps to execute") if steps.empty?

            results = @executor.execute_many(steps, context: context)
            context.concat(results)
            trace << { iteration: iteration, results: results, timestamp: Time.now }
          else
            # Unknown action type, create empty results array
            results = []
          end

          # Check for stop condition
          stop_reason = plan["stop_reason"] || plan[:stop_reason]
          return build_result(context, trace, "completed", stop_reason) if stop_reason && !stop_reason.empty?

          # Check if we should continue (only if results is not nil/empty)
          return build_result(context, trace, "completed", "Stop condition met") if results && should_stop?(results)
        end

        build_result(context, trace, "max_iterations", "Reached max iterations: #{@max_iterations}")
      end

      private

      def task_with_context(task, context)
        return task if context.empty?

        <<~TEXT
          #{task}

          PREVIOUS RESULTS:
          #{JSON.pretty_generate(context)}
        TEXT
      end

      def timeout_reached?
        return false unless @start_time

        (Time.now - @start_time) > @timeout
      end

      def should_stop?(results)
        # Stop if all results indicate error (not success)
        return false unless results && results.respond_to?(:all?) && !results.empty?
        # Only stop if ALL results are errors
        results.all? { |r|
          status = r["status"] || r[:status]
          status == "error" || status == "rejected"
        }
      end

      def build_result(context, trace, status, reason)
        {
          status: status,
          reason: reason,
          context: context,
          trace: trace,
          iterations: trace.select { |t| t[:plan] }.length,
          duration: @start_time ? (Time.now - @start_time) : 0
        }
      end
    end
  end
end
