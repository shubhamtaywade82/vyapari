# frozen_string_literal: true

require_relative "tool_registry"
require_relative "safety_gate"

module Ollama
  class Agent
    # Executes tool calls from planner output
    # Handles sequential or parallel execution with safety limits
    class Executor
      def initialize(registry: nil, tools: nil, max_parallel: 1, safety_gate: nil)
        @registry = registry
        @tools = tools # Legacy support
        @max_parallel = max_parallel
        @safety_gate = safety_gate
        @execution_log = []
      end

      # Execute a single tool call
      # @param tool_name [String] Name of tool to call
      # @param args [Hash] Tool arguments
      # @param context [Hash] Execution context for safety checks
      # @return [Hash] Tool result with status and data
      def execute(tool_name:, args: {}, context: {}) # rubocop:disable Lint/UnusedMethodArgument
        # Use registry if available, fall back to legacy tools
        if @registry
          # Safety gate check
          if @safety_gate
            descriptor = @registry.descriptor(tool_name)
            if descriptor
              safety_check = @safety_gate.check(
                tool_name: tool_name,
                args: args,
                descriptor: descriptor
              )

              unless safety_check[:allowed]
                log_execution(tool_name, args, nil, "safety_blocked", safety_check[:reason])
                return {
                  status: "error",
                  error: "Safety gate blocked execution: #{safety_check[:reason]}",
                  tool: tool_name,
                  args: args,
                  safety_errors: safety_check[:errors]
                }
              end
            end
          end

          result = @registry.call(tool_name, args)
          log_execution(tool_name, args, result[:result], result[:status], result[:error])
          result
        else
          # Legacy mode - use @tools hash
          tool = @tools[tool_name.to_sym] || @tools[tool_name.to_s]

          unless tool
            return {
              status: "error",
              error: "Tool '#{tool_name}' not found",
              tool: tool_name,
              args: args
            }
          end

          begin
            result = call_tool(tool, args)
            log_execution(tool_name, args, result, "success")
            {
              status: "success",
              tool: tool_name,
              args: args,
              result: result
            }
          rescue StandardError => e
            log_execution(tool_name, args, nil, "error", e.message)
            {
              status: "error",
              tool: tool_name,
              args: args,
              error: e.message
            }
          end
        end
      end

      # Execute multiple tool calls (sequential by default)
      # @param steps [Array<Hash>] Array of {tool:, args:} hashes
      # @return [Array<Hash>] Array of execution results
      def execute_many(steps)
        if @max_parallel > 1 && steps.length > 1
          execute_parallel(steps)
        else
          execute_sequential(steps)
        end
      end

      # Get execution log
      # @return [Array<Hash>] Log of all executions
      def execution_log
        @execution_log.dup
      end

      private

      def call_tool(tool, args)
        case tool
        when Proc, Method
          tool.call(args)
        when Class
          tool.new.call(args)
        else
          raise ExecutorError, "Invalid tool type: #{tool.class}"
        end
      end

      def execute_sequential(steps, context: {})
        steps.map do |step|
          execute(
            tool_name: step["tool"] || step[:tool],
            args: step["args"] || step[:args] || {},
            context: context
          )
        end
      end

      def execute_parallel(steps, context: {})
        # Simple parallel execution (can be enhanced with threads/pools)
        # For now, fall back to sequential
        execute_sequential(steps, context: context)
      end

      def log_execution(tool_name, args, result, status, error = nil)
        @execution_log << {
          tool: tool_name,
          args: args,
          result: result,
          status: status,
          error: error,
          timestamp: Time.now
        }
      end
    end

    class ExecutorError < StandardError; end
  end
end
