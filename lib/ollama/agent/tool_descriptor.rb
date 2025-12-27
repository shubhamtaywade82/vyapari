# frozen_string_literal: true

module Ollama
  class Agent
    # Formal tool descriptor - defines tool contract for LLM
    # This is what the LLM sees, not Ruby code
    class ToolDescriptor
      attr_reader :name, :description, :when_to_use, :when_not_to_use,
                  :inputs, :outputs, :side_effects, :safety_rules, :category, :risk_level

      def initialize(name:, description:, inputs:, outputs:,
                     when_to_use: nil, when_not_to_use: nil,
                     side_effects: [], safety_rules: [],
                     category: nil, risk_level: :none)
        @name = name
        @description = description
        @when_to_use = when_to_use
        @when_not_to_use = when_not_to_use
        @inputs = normalize_schema(inputs)
        @outputs = normalize_schema(outputs)
        @side_effects = Array(side_effects)
        @safety_rules = Array(safety_rules)
        @category = category
        @risk_level = risk_level
      end

      # Convert to JSON schema format for LLM
      def to_schema
        schema = {
          name: @name,
          description: @description,
          when_to_use: @when_to_use,
          when_not_to_use: @when_not_to_use,
          inputs: @inputs,
          outputs: @outputs,
          side_effects: @side_effects,
          safety_rules: @safety_rules
        }
        schema[:category] = @category if @category
        schema[:risk_level] = @risk_level
        schema
      end

      # Convert to JSON string for prompt injection
      def to_json
        require "json"
        JSON.generate(to_schema)
      end

      # Validate input arguments against schema
      def validate_input(args)
        errors = []
        args = normalize_hash(args)

        # Check required fields
        if @inputs["required"]
          @inputs["required"].each do |field|
            unless args.key?(field.to_s) || args.key?(field.to_sym)
              errors << "Missing required field: #{field}"
            end
          end
        end

        # Validate field types and constraints
        if @inputs["properties"]
          @inputs["properties"].each do |field, schema|
            value = args[field.to_s] || args[field.to_sym]
            next unless value

            field_errors = validate_field(value, schema, field)
            errors.concat(field_errors)
          end
        end

        { valid: errors.empty?, errors: errors }
      end

      private

      def normalize_schema(schema)
        case schema
        when Hash
          schema.transform_keys(&:to_s)
        else
          { "type" => "object", "properties" => {} }
        end
      end

      def normalize_hash(hash)
        hash.transform_keys(&:to_s)
      end

      def validate_field(value, schema, field_name)
        errors = []

        # Type validation
        expected_type = schema["type"] || schema[:type]
        if expected_type
          type_ok = case expected_type
                    when "string"
                      value.is_a?(String)
                    when "integer"
                      value.is_a?(Integer)
                    when "number"
                      value.is_a?(Numeric)
                    when "boolean"
                      value.is_a?(TrueClass) || value.is_a?(FalseClass)
                    when "object"
                      value.is_a?(Hash)
                    when "array"
                      value.is_a?(Array)
                    else
                      true # Unknown type, skip validation
                    end

          errors << "#{field_name}: expected #{expected_type}, got #{value.class}" unless type_ok
        end

        # Enum validation
        if schema["enum"] || schema[:enum]
          enum_values = schema["enum"] || schema[:enum]
          unless enum_values.include?(value)
            errors << "#{field_name}: must be one of #{enum_values.join(", ")}"
          end
        end

        # Min/Max validation
        if schema["minimum"] && value.is_a?(Numeric)
          errors << "#{field_name}: must be >= #{schema["minimum"]}" if value < schema["minimum"]
        end

        if schema["maximum"] && value.is_a?(Numeric)
          errors << "#{field_name}: must be <= #{schema["maximum"]}" if value > schema["maximum"]
        end

        errors
      end
    end
  end
end

