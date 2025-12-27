# frozen_string_literal: true

module Ollama
  class Agent
    # Executes tool calls from planner output
    # Handles sequential or parallel execution with safety limits
    class Executor
      def initialize(tools:, max_parallel: 1)
        @tools = tools
        @max_parallel = max_parallel
        @execution_log = []
      end

      # Execute a single tool call
      # @param tool_name [String] Name of tool to call
      # @param args [Hash] Tool arguments
      # @return [Hash] Tool result with status and data
      def execute(tool_name:, args: {})
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

      def execute_sequential(steps)
        steps.map do |step|
          execute(tool_name: step["tool"] || step[:tool], args: step["args"] || step[:args] || {})
        end
      end

      def execute_parallel(steps)
        # Simple parallel execution (can be enhanced with threads/pools)
        # For now, fall back to sequential
        execute_sequential(steps)
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
