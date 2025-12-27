# frozen_string_literal: true

module Ollama
  class Agent
    # Safety gate for trading tools - validates before execution
    # LLMs DO NOT manage risk - YOU DO
    class SafetyGate
      def initialize(rules: [])
        @rules = rules
        @context = {}
      end

      # Set execution context (for stateful validation)
      # @param context [Hash] Context data
      def context=(context)
        @context = context.is_a?(Hash) ? context : {}
      end

      # Check if tool execution is allowed
      # @param tool_name [String] Tool name
      # @param args [Hash] Tool arguments
      # @param descriptor [ToolDescriptor] Tool descriptor
      # @return [Hash] { allowed: Boolean, reason: String, errors: Array }
      def check(tool_name:, args:, descriptor:)
        errors = []

        # Check custom rules
        @rules.each do |rule|
          rule_result = rule.call(tool_name: tool_name, args: args, context: @context, descriptor: descriptor)
          if rule_result.is_a?(Hash) && !rule_result[:allowed]
            errors << rule_result[:reason] || "Safety rule violation"
          elsif rule_result.is_a?(String)
            errors << rule_result
          end
        end

        # Check descriptor safety rules
        descriptor.safety_rules.each do |rule|
          # Simple string rules
          if rule.is_a?(String)
            # Check if rule mentions required context
            if rule.include?("stoploss") && !@context.key?(:stoploss) && !@context.key?("stoploss")
              errors << "Safety rule: #{rule} (missing stoploss in context)"
            end
          end
        end

        {
          allowed: errors.empty?,
          reason: errors.empty? ? nil : errors.join("; "),
          errors: errors
        }
      end

      # Trading-specific safety rules factory
      # @return [Array<Proc>] Array of safety rule procs
      def self.trading_rules(max_position_size: nil, require_stoploss: true, dry_run_only: false)
        rules = []

        # Rule: Never place order without stoploss
        if require_stoploss
          rules << lambda do |tool_name:, args:, context:, **|
            if tool_name.include?("place_order") || tool_name.include?("order")
              unless context[:stoploss] || context["stoploss"]
                { allowed: false, reason: "Cannot place order without stoploss in context" }
              end
            end
          end
        end

        # Rule: Never exceed max position size
        if max_position_size
          rules << lambda do |tool_name:, args:, context:, **|
            if tool_name.include?("place_order") || tool_name.include?("order")
              quantity = args[:quantity] || args["quantity"] || 0
              current_position = context[:position_size] || context["position_size"] || 0

              if (current_position + quantity) > max_position_size
                {
                  allowed: false,
                  reason: "Order would exceed max position size: #{current_position + quantity} > #{max_position_size}"
                }
              end
            end
          end
        end

        # Rule: Dry-run only mode
        if dry_run_only
          rules << lambda do |tool_name:, args:, **|
            if tool_name.include?("place_order") || tool_name.include?("order")
              unless ENV["DRY_RUN"] == "true" || ENV["DRY_RUN_MODE"] == "true"
                { allowed: false, reason: "Trading disabled - dry-run mode required" }
              end
            end
          end
        end

        rules
      end
    end
  end
end

