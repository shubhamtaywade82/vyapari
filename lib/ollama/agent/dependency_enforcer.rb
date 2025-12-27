# frozen_string_literal: true

module Ollama
  class Agent
    # Enforces tool dependencies before execution
    # Prevents LLM from calling tools out of order or skipping prerequisites
    class DependencyEnforcer
      def initialize(registry: nil)
        @registry = registry
      end

      # Validate all dependencies for a tool before execution
      # @param tool_name [String] Tool name
      # @param context [Hash] Execution context (state, outputs, guards, tool_calls)
      # @return [Hash] { valid: Boolean, errors: Array<String> }
      def validate(tool_name:, context: {})
        descriptor = @registry&.descriptor(tool_name)
        return { valid: true, errors: [] } unless descriptor&.dependencies

        deps = descriptor.dependencies
        errors = []

        # ① Data dependency: required_outputs
        deps["required_outputs"]&.each do |output_key|
          unless context_has_key?(context, output_key)
            errors << "Missing required output: #{output_key} (from previous tool)"
          end
        end

        # ② State dependency: required_states
        deps["required_states"]&.each do |required_state|
          current_state = context[:state] || context["state"]
          unless current_state == required_state || current_state.to_s == required_state.to_s
            errors << "Invalid state: required '#{required_state}', current '#{current_state}'"
          end
        end

        # ③ Safety dependency: required_guards
        deps["required_guards"]&.each do |guard_name|
          guards_passed = context[:guards_passed] || context["guards_passed"] || []
          unless guards_passed.include?(guard_name) || guards_passed.include?(guard_name.to_s)
            errors << "Guard not passed: #{guard_name}"
          end
        end

        # ④ Temporal dependency: forbidden_after
        deps["forbidden_after"]&.each do |forbidden_event|
          events = context[:events] || context["events"] || []
          if events.include?(forbidden_event) || events.include?(forbidden_event.to_s)
            errors << "Tool forbidden after event: #{forbidden_event}"
          end
        end

        # ④ Temporal dependency: max_calls_per_trade
        if deps["max_calls_per_trade"]
          tool_calls = context[:tool_calls] || context["tool_calls"] || {}
          call_count = tool_calls[tool_name] || tool_calls[tool_name.to_s] || 0
          if call_count >= deps["max_calls_per_trade"]
            errors << "Tool call limit exceeded: max #{deps["max_calls_per_trade"]} per trade, already called #{call_count} times"
          end
        end

        # ① Data dependency: required_tools (must have been called)
        deps["required_tools"]&.each do |required_tool|
          tool_calls = context[:tool_calls] || context["tool_calls"] || {}
          unless tool_calls.key?(required_tool) || tool_calls.key?(required_tool.to_s)
            errors << "Required tool not called: #{required_tool}"
          end
        end

        {
          valid: errors.empty?,
          errors: errors
        }
      end

      private

      # Check if context has a key (supports nested keys like "validated_trade_plan.quantity")
      def context_has_key?(context, key)
        keys = key.to_s.split(".")
        current = context

        keys.each do |k|
          return false unless current.is_a?(Hash)

          current = current[k.to_sym] || current[k.to_s]
          return false unless current
        end

        true
      end
    end
  end
end
