# frozen_string_literal: true

# Cursor-style debug loop for Vyapari
# Edit → Run → Observe → Fix pattern

module Vyapari
  module Tools
    class DebugLoop
      attr_reader :iterations, :max_iterations, :context, :trace

      def initialize(max_iterations: 10, logger: nil)
        @max_iterations = max_iterations
        @logger = logger || default_logger
        @iterations = 0
        @context = {}
        @trace = []
      end

      # Run debug loop with edit → run → observe → fix pattern
      # @param initial_task [String] Initial task
      # @param planner [Object] Planner that generates tool calls
      # @param executor [Object] Executor that runs tools
      # @yield [iteration, context, result] Block to observe results
      def run(initial_task:, planner:, executor:)
        @logger.info "🔧 Starting debug loop for: #{initial_task}"
        @iterations = 0
        @context = { task: initial_task }
        @trace = []

        while @iterations < @max_iterations
          @iterations += 1
          @logger.info "📝 Iteration #{@iterations}/#{@max_iterations}"

          # STEP 1: Plan (Edit phase - LLM generates plan)
          plan = planner.plan(task: @context[:task], context: @context)
          @trace << { iteration: @iterations, phase: "plan", data: plan }

          # Check if done
          if plan[:action] == "final"
            @logger.info "✅ Task completed: #{plan[:final_output]}"
            return build_result("completed", plan[:final_output])
          end

          # STEP 2: Execute (Run phase)
          if plan[:action] == "tool_call"
            result = executor.execute(
              tool_name: plan[:tool_name],
              args: plan[:tool_args],
              context: @context
            )
            @trace << { iteration: @iterations, phase: "execute", data: result }

            # STEP 3: Observe (Observe phase)
            observation = observe_result(result)
            @context[:last_result] = result
            @context[:last_observation] = observation

            # Yield to caller for custom observation
            yield(@iterations, @context, result) if block_given?

            # STEP 4: Fix (Fix phase - update context for next iteration)
            if result[:status] == "error"
              @logger.warn "⚠️  Tool execution failed: #{result[:error]}"
              @context[:errors] ||= []
              @context[:errors] << result[:error]

              # Auto-fix: retry with corrected args if possible
              if should_retry?(result)
                @logger.info "🔄 Auto-retrying with corrected arguments"
                next
              end
            else
              # Success: add result to context
              @context[:results] ||= []
              @context[:results] << result
            end
          else
            @logger.warn "⚠️  Unknown action: #{plan[:action]}"
            break
          end
        end

        build_result("max_iterations", "Reached max iterations: #{@max_iterations}")
      end

      private

      def observe_result(result)
        {
          status: result[:status],
          tool: result[:tool],
          success: result[:status] == "success",
          error: result[:error],
          timestamp: Time.now
        }
      end

      def should_retry?(result)
        # Auto-retry logic for common errors
        error = result[:error] || ""

        # Retry if it's a validation error (might be fixable)
        return false if error.include?("REJECTED")
        return false if error.include?("INVALID")

        # Don't retry if it's a fundamental error
        return false if error.include?("not found")
        return false if error.include?("unauthorized")

        # Retry for transient errors
        true if error.include?("timeout") || error.include?("network")
      end

      def build_result(status, output)
        {
          status: status,
          output: output,
          iterations: @iterations,
          context: @context,
          trace: @trace
        }
      end

      def default_logger
        require "logger"
        Logger.new($stdout)
      end
    end
  end
end

