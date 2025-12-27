# frozen_string_literal: true

module Ollama
  class Agent
    # Validates planner output and tool results
    # Enforces safety rules and schema compliance
    class Verifier
      def initialize(schema: nil, safety_rules: [])
        @schema = schema
        @safety_rules = safety_rules
      end

      # Verify a plan matches expected schema
      # @param plan [Hash] Plan to verify
      # @return [Hash] Verification result with valid: boolean and errors: array
      def verify_plan(plan)
        errors = []

        # Schema validation
        if @schema
          schema_errors = validate_schema(plan, @schema)
          errors.concat(schema_errors)
        end

        # Safety rule validation
        @safety_rules.each do |rule|
          rule_errors = rule.call(plan)
          errors.concat(rule_errors) if rule_errors.is_a?(Array)
        end

        {
          valid: errors.empty?,
          errors: errors
        }
      end

      # Verify tool execution result
      # @param result [Hash] Tool execution result
      # @return [Hash] Verification result
      def verify_result(result)
        errors = []

        unless result.is_a?(Hash)
          errors << "Result must be a Hash"
          return { valid: false, errors: errors }
        end

        errors << "Result must have 'status' field" unless result["status"] || result[:status]

        if result["status"] == "error" || result[:status] == "error"
          errors << "Tool execution failed: #{result["error"] || result[:error]}"
        end

        {
          valid: errors.empty?,
          errors: errors
        }
      end

      # Verify final output before returning
      # @param output [Hash] Final agent output
      # @return [Hash] Verification result
      def verify_final(output)
        errors = []

        errors << "Final output must be a Hash" unless output.is_a?(Hash)

        {
          valid: errors.empty?,
          errors: errors
        }
      end

      private

      def validate_schema(data, schema)
        errors = []

        case schema["type"]
        when "object"
          errors.concat(validate_object(data, schema))
        when "array"
          errors.concat(validate_array(data, schema))
        end

        errors
      end

      def validate_object(data, schema)
        errors = []

        return ["Expected object, got #{data.class}"] unless data.is_a?(Hash)

        # Check required properties
        if schema["required"]
          schema["required"].each do |prop|
            errors << "Missing required property: #{prop}" unless data.key?(prop) || data.key?(prop.to_sym)
          end
        end

        # Validate properties
        if schema["properties"]
          schema["properties"].each do |prop, prop_schema|
            value = data[prop] || data[prop.to_sym]
            next unless value

            prop_errors = validate_schema(value, prop_schema)
            errors.concat(prop_errors.map { |e| "#{prop}: #{e}" })
          end
        end

        errors
      end

      def validate_array(data, schema)
        errors = []

        return ["Expected array, got #{data.class}"] unless data.is_a?(Array)

        items_schema = schema["items"]
        return errors unless items_schema

        data.each_with_index do |item, index|
          item_errors = validate_schema(item, items_schema)
          errors.concat(item_errors.map { |e| "[#{index}]: #{e}" })
        end

        errors
      end
    end
  end
end
