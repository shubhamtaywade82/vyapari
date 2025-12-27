# frozen_string_literal: true

require_relative "tool_descriptor"

module Ollama
  class Agent
    # Registry for managing tool descriptors and handlers
    # Similar to Cursor's tool system
    class ToolRegistry
      def initialize
        @tools = {}
      end

      # Register a tool with descriptor and handler
      # @param descriptor [ToolDescriptor, Hash] Tool descriptor
      # @param handler [Proc, Method, Object] Tool execution handler
      def register(descriptor:, handler:)
        descriptor = ToolDescriptor.new(**descriptor) if descriptor.is_a?(Hash)
        name = descriptor.name

        if @tools.key?(name)
          raise RegistryError, "Tool '#{name}' is already registered"
        end

        @tools[name] = {
          descriptor: descriptor,
          handler: handler
        }
      end

      # Get tool descriptor by name
      # @param name [String] Tool name
      # @return [ToolDescriptor, nil]
      def descriptor(name)
        @tools[name]&.dig(:descriptor)
      end

      # Get all tool descriptors as JSON schema array
      # @return [Array<Hash>] Array of tool schemas
      def descriptors
        @tools.values.map { |tool| tool[:descriptor].to_schema }
      end

      # Get all tool descriptors as JSON string (for prompt injection)
      # @return [String] JSON string
      def descriptors_json
        require "json"
        JSON.pretty_generate(descriptors)
      end

      # Execute a tool by name
      # @param name [String] Tool name
      # @param args [Hash] Tool arguments
      # @return [Hash] Tool result
      def call(name, args = {})
        tool = @tools[name]

        unless tool
          return {
            status: "error",
            error: "Tool '#{name}' not found",
            tool: name,
            args: args
          }
        end

        descriptor = tool[:descriptor]
        handler = tool[:handler]

        # Validate inputs
        validation = descriptor.validate_input(args)
        unless validation[:valid]
          return {
            status: "error",
            error: "Invalid arguments: #{validation[:errors].join(", ")}",
            tool: name,
            args: args,
            validation_errors: validation[:errors]
          }
        end

        # Execute handler
        begin
          result = call_handler(handler, args)
          {
            status: "success",
            tool: name,
            args: args,
            result: result
          }
        rescue StandardError => e
          {
            status: "error",
            tool: name,
            args: args,
            error: e.message,
            backtrace: e.backtrace&.first(3)
          }
        end
      end

      # Check if tool exists
      # @param name [String] Tool name
      # @return [Boolean]
      def exists?(name)
        @tools.key?(name)
      end

      # List all registered tool names
      # @return [Array<String>]
      def tool_names
        @tools.keys
      end

      private

      def call_handler(handler, args)
        case handler
        when Proc, Method
          handler.call(args)
        when Class
          handler.new.call(args)
        else
          if handler.respond_to?(:call)
            handler.call(args)
          else
            raise RegistryError, "Invalid handler type: #{handler.class}"
          end
        end
      end
    end

    class RegistryError < StandardError; end
  end
end

