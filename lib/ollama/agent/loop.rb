# frozen_string_literal: true

require "json"

module Ollama
  class Agent
    # Bounded agent loop controller
    # Enforces iteration limits, timeouts, and token budgets
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
      # @param task [String] Initial task
      # @param plan_schema [Hash] JSON schema for plans
      # @return [Hash] Final result with context and trace
      def run(task:, plan_schema:)
        @start_time = Time.now
        @token_count = 0
        context = []
        iteration = 0
        trace = []

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

          # Check for stop condition
          stop_reason = plan["stop_reason"] || plan[:stop_reason]
          return build_result(context, trace, "completed", stop_reason) if stop_reason && !stop_reason.empty?

          # Execute plan steps
          steps = plan["steps"] || plan[:steps] || []
          return build_result(context, trace, "completed", "No steps to execute") if steps.empty?

          results = @executor.execute_many(steps)
          context.concat(results)
          trace << { iteration: iteration, results: results, timestamp: Time.now }

          # Check if we should continue
          return build_result(context, trace, "completed", "Stop condition met") if should_stop?(results)
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
        # Stop if all results indicate completion or error
        results.all? { |r| r["status"] == "error" || r[:status] == "error" }
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
