# frozen_string_literal: true

module Ollama
  class Agent
    # Formal tool descriptor - defines tool contract for LLM
    # This is what the LLM sees, not Ruby code
    class ToolDescriptor
      attr_reader :name, :description, :when_to_use, :when_not_to_use,
                  :inputs, :outputs, :side_effects, :safety_rules, :category, :risk_level,
                  :dependencies

      def initialize(name:, description:, inputs:, outputs:,
                     when_to_use: nil, when_not_to_use: nil,
                     side_effects: [], safety_rules: [],
                     category: nil, risk_level: :none,
                     dependencies: nil)
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
        @dependencies = normalize_dependencies(dependencies)
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
        schema[:dependencies] = @dependencies if @dependencies && !@dependencies.empty?
        schema
      end

      # Convert to JSON string for prompt injection
      def to_json(*_args)
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
            errors << "Missing required field: #{field}" unless args.key?(field.to_s) || args.key?(field.to_sym)
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
          normalized = schema.transform_keys(&:to_s)
          # Recursively normalize nested properties
          if normalized["properties"] && normalized["properties"].is_a?(Hash)
            normalized["properties"] = normalized["properties"].transform_keys(&:to_s).transform_values do |prop_schema|
              if prop_schema.is_a?(Hash)
                prop_schema.transform_keys(&:to_s)
              else
                prop_schema
              end
            end
          end
          normalized
        else
          { "type" => "object", "properties" => {} }
        end
      end

      def normalize_hash(hash)
        hash.transform_keys(&:to_s)
      end

      def normalize_dependencies(deps)
        return nil unless deps

        normalized = deps.is_a?(Hash) ? deps.transform_keys(&:to_s) : {}
        {
          "required_tools" => Array(normalized["required_tools"] || normalized[:required_tools]),
          "required_outputs" => Array(normalized["required_outputs"] || normalized[:required_outputs]),
          "required_states" => Array(normalized["required_states"] || normalized[:required_states]),
          "required_guards" => Array(normalized["required_guards"] || normalized[:required_guards]),
          "forbidden_after" => Array(normalized["forbidden_after"] || normalized[:forbidden_after]),
          "forbidden_states" => Array(normalized["forbidden_states"] || normalized[:forbidden_states]),
          "forbidden_callers" => Array(normalized["forbidden_callers"] || normalized[:forbidden_callers]),
          "max_calls_per_trade" => normalized["max_calls_per_trade"] || normalized[:max_calls_per_trade],
          "derived_inputs" => normalized["derived_inputs"] || normalized[:derived_inputs] || {},
          "produces" => Array(normalized["produces"] || normalized[:produces]),
          "date_constraints" => normalized["date_constraints"] || normalized[:date_constraints] || {}
        }
      end

      def validate_field(value, schema, field_name)
        errors = []

        # Type validation
        expected_type = schema["type"] || schema[:type]
        if expected_type
          # Handle array of types (e.g., ["string", "integer"])
          types_to_check = expected_type.is_a?(Array) ? expected_type : [expected_type]

          type_ok = types_to_check.any? do |type|
            case type
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
          end

          unless type_ok
            type_str = expected_type.is_a?(Array) ? expected_type.join(" or ") : expected_type
            errors << "#{field_name}: expected #{type_str}, got #{value.class}"
          end
        end

        # Enum validation
        if schema["enum"] || schema[:enum]
          enum_values = schema["enum"] || schema[:enum]
          errors << "#{field_name}: must be one of #{enum_values.join(", ")}" unless enum_values.include?(value)
        end

        # Min/Max validation
        if schema["minimum"] && value.is_a?(Numeric) && (value < schema["minimum"])
          errors << "#{field_name}: must be >= #{schema["minimum"]}"
        end

        if schema["maximum"] && value.is_a?(Numeric) && (value > schema["maximum"])
          errors << "#{field_name}: must be <= #{schema["maximum"]}"
        end

        errors
      end
    end
  end
end
