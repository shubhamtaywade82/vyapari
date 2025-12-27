# frozen_string_literal: true

require_relative "tool_registry"
require_relative "safety_gate"
require_relative "dependency_enforcer"

module Ollama
  class Agent
    # Executes tool calls from planner output
    # Handles sequential or parallel execution with safety limits
    class Executor
      def initialize(registry: nil, tools: nil, max_parallel: 1, safety_gate: nil, dependency_enforcer: nil)
        @registry = registry
        @tools = tools # Legacy support
        @max_parallel = max_parallel
        @safety_gate = safety_gate
        @dependency_enforcer = dependency_enforcer || (registry ? DependencyEnforcer.new(registry: registry) : nil)
        @execution_log = []
      end

      # Execute a single tool call
      # @param tool_name [String] Name of tool to call
      # @param args [Hash] Tool arguments
      # @param context [Hash] Execution context for safety checks
      # @return [Hash] Tool result with status and data
      def execute(tool_name:, args: {}, context: {})
        # Use registry if available, fall back to legacy tools
        if @registry
          # ① Dependency validation (FIRST - before safety gate)
          if @dependency_enforcer
            dep_check = @dependency_enforcer.validate(tool_name: tool_name, context: context)
            unless dep_check[:valid]
              log_execution(tool_name, args, nil, "dependency_blocked", dep_check[:errors].join("; "))
              return {
                status: "error",
                error: "Dependency validation failed: #{dep_check[:errors].join("; ")}",
                tool: tool_name,
                args: args,
                dependency_errors: dep_check[:errors]
              }
            end

            # ①.5 Resolve derived inputs from context (after validation, before execution)
            args = @dependency_enforcer.resolve_derived_inputs(tool_name: tool_name, args: args, context: context)
          end

          # ② Safety gate check
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
      # @param context [Hash] Execution context (optional, for dependency tracking)
      # @return [Array<Hash>] Array of execution results
      def execute_many(steps, context: {})
        if @max_parallel > 1 && steps.length > 1
          execute_parallel(steps, context: context)
        else
          execute_sequential(steps, context: context)
        end
      end

      # Get execution log
      # @return [Array<Hash>] Log of all executions
      def execution_log
        @execution_log.dup
      end

      # Get registry (for context building)
      # @return [ToolRegistry] Tool registry
      attr_reader :registry

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
        # Build context as hash if it's not already
        exec_context = context.is_a?(Hash) ? context.dup : { tool_calls: {}, results: [] }
        exec_context[:tool_calls] ||= {}
        exec_context[:results] ||= []

        results = steps.map do |step|
          tool_name = step["tool"] || step[:tool]
          tool_args = step["args"] || step[:args] || {}

          result = execute(
            tool_name: tool_name,
            args: tool_args,
            context: exec_context
          )

          # Update context after each execution
          update_context_from_result(exec_context, tool_name, result)

          result
        end

        results
      end

      # Update context with tool result (for sequential execution)
      def update_context_from_result(context, tool_name, result)
        return unless context.is_a?(Hash)

        # Track tool call
        context[:tool_calls] ||= {}
        context[:tool_calls][tool_name] = (context[:tool_calls][tool_name] || 0) + 1
        context[:results] ||= []
        context[:results] << result

        # Extract outputs based on tool descriptor's "produces" field
        return unless @registry && result && result[:status] == "success"

        descriptor = @registry.descriptor(tool_name)
        return unless descriptor&.dependencies

        produces = descriptor.dependencies["produces"] || []
        return if produces.empty?

        tool_result = result[:result] || result["result"] || {}

        produces.each do |output_key|
          case output_key
          when "instrument"
            if tool_result.is_a?(Hash)
              context[:instrument] = tool_result
            elsif result.is_a?(Hash) && result[:result]
              context[:instrument] = result[:result]
            end
          when "expiry_list"
            if tool_result.is_a?(Array)
              context[:expiry_list] = tool_result
            elsif tool_result.is_a?(Hash)
              context[:expiry_list] = tool_result[:expiries] || tool_result["expiries"] ||
                                      tool_result[:data] || tool_result["data"] || []
            elsif result.is_a?(Hash) && result[:result].is_a?(Array)
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
            context[output_key.to_sym] = tool_result
          end
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
