# frozen_string_literal: true

module Vyapari
  module Tools
    # Registry for managing tool classes
    class Registry
      def initialize
        @tools = {}
      end

      def register(tool_class)
        @tools[tool_class.name] = tool_class
      end

      def fetch(name)
        @tools.fetch(name) { raise "Tool not found: #{name}" }
      end

      def tool_schemas
        @tools.values.map(&:schema)
      end
    end
  end
end

