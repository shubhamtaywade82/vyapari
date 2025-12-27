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
        # Context is now a hash with tool_calls and outputs (not an array)
        context = {
          tool_calls: {},
          results: [] # Keep results array for backward compatibility with task_with_context
        }
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

            # Update context: track tool call and extract outputs
            update_context_from_result(context, tool_name, result, @executor.registry)

            # Keep results array for backward compatibility
            context[:results] << result
            trace << { iteration: iteration, tool_call: { tool: tool_name, args: tool_args }, result: result,
                       timestamp: Time.now }

            # For tool_call, check if result indicates error
            results = [result]

          elsif action.nil? || action.empty?
            # Legacy: support steps array format
            steps = plan["steps"] || plan[:steps] || []
            return build_result(context, trace, "completed", "No steps to execute") if steps.empty?

            results = @executor.execute_many(steps, context: context)

            # Update context for each result
            results.each_with_index do |result, idx|
              step = steps[idx]
              tool_name = step["tool"] || step[:tool] || step["name"] || step[:name]
              next unless tool_name
              update_context_from_result(context, tool_name, result, @executor.registry)
            end

            # Keep results array for backward compatibility
            context[:results].concat(results)
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
        # Use results array for LLM context (backward compatibility)
        results = context.is_a?(Hash) ? context[:results] : context
        return task if results.empty?

        <<~TEXT
          #{task}

          PREVIOUS RESULTS:
          #{JSON.pretty_generate(results)}
        TEXT
      end

      # Update context hash with tool call tracking and output extraction
      def update_context_from_result(context, tool_name, result, registry)
        return unless context.is_a?(Hash)

        # Track tool call
        context[:tool_calls] ||= {}
        context[:tool_calls][tool_name] = (context[:tool_calls][tool_name] || 0) + 1

        # Extract outputs based on tool descriptor's "produces" field
        return unless registry && result && result[:status] == "success"

        descriptor = registry.descriptor(tool_name)
        return unless descriptor&.dependencies

        produces = descriptor.dependencies["produces"] || []
        return if produces.empty?

        tool_result = result[:result] || result["result"] || {}

        produces.each do |output_key|
          # Map output_key to actual result data
          # For example: "instrument" -> extract from result
          #              "expiry_list" -> extract from result
          case output_key
          when "instrument"
            # Store instrument data from result
            if tool_result.is_a?(Hash)
              context[:instrument] = tool_result
            elsif result.is_a?(Hash) && result[:result]
              context[:instrument] = result[:result]
            end
          when "expiry_list"
            # Store expiry list from result
            # The tool handler returns an array directly, but executor wraps it
            if tool_result.is_a?(Array)
              context[:expiry_list] = tool_result
            elsif tool_result.is_a?(Hash)
              # Try common keys
              context[:expiry_list] = tool_result[:expiries] || tool_result["expiries"] ||
                                      tool_result[:data] || tool_result["data"] || []
            elsif result.is_a?(Hash) && result[:result].is_a?(Array)
              # If result[:result] is the array directly
              context[:expiry_list] = result[:result]
            end
          when "intraday_candles"
            context[:intraday_candles] = tool_result[:candles] || tool_result["candles"] || tool_result
          when "daily_candles"
            context[:daily_candles] = tool_result[:candles] || tool_result["candles"] || tool_result
          when "option_chain_snapshot"
            context[:option_chain_snapshot] = tool_result
          when "available_capital"
            context[:available_capital] = tool_result[:available] || tool_result["available"] || tool_result
          when "open_positions"
            context[:open_positions] = tool_result[:positions] || tool_result["positions"] || tool_result
          when "holdings"
            context[:holdings] = tool_result[:holdings] || tool_result["holdings"] || tool_result
          when "orders"
            context[:orders] = tool_result[:orders] || tool_result["orders"] || tool_result
          when "trades"
            context[:trades] = tool_result[:trades] || tool_result["trades"] || tool_result
          when "order_id"
            context[:order_id] = tool_result[:order_id] || tool_result["order_id"]
          else
            # Generic: store with output_key as the context key
            context[output_key.to_sym] = tool_result
          end
        end
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
        # Convert context hash back to array format for backward compatibility
        result_context = context.is_a?(Hash) ? context[:results] : context

        {
          status: status,
          reason: reason,
          context: result_context,
          trace: trace,
          iterations: trace.select { |t| t[:plan] }.length,
          duration: @start_time ? (Time.now - @start_time) : 0
        }
      end
    end
  end
end
