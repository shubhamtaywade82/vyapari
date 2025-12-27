# frozen_string_literal: true

# Adapter to register EnhancedDhanTools into Ollama::Agent::ToolRegistry
# Bridges the gap between enhanced tool descriptors and the agent system

require_relative "enhanced_dhan_tools"
require_relative "../../ollama/agent/tool_registry"
require_relative "../../ollama/agent/tool_descriptor"
require_relative "../../ollama/agent/tools/dhan_tools"

module Vyapari
  module Tools
    class ToolRegistryAdapter
      # Register all enhanced DhanHQ tools into an Ollama ToolRegistry
      # @param registry [Ollama::Agent::ToolRegistry] Target registry
      # @param dhan_client [Object, nil] DhanHQ client for handlers
      # @return [Ollama::Agent::ToolRegistry] Registry with tools registered
      def self.register_enhanced_tools(registry:, dhan_client: nil)
        EnhancedDhanTools.all.each do |enhanced_descriptor|
          # Convert enhanced descriptor to ToolDescriptor format
          ollama_descriptor = convert_to_ollama_descriptor(enhanced_descriptor)

          # Get handler for this tool
          handler = get_handler_for_tool(enhanced_descriptor[:name], dhan_client)

          # Register in registry
          registry.register(
            descriptor: ollama_descriptor,
            handler: handler
          )
        end

        registry
      end

      # Convert enhanced tool descriptor to Ollama ToolDescriptor
      # @param enhanced [Hash] Enhanced tool descriptor
      # @return [Ollama::Agent::ToolDescriptor] Ollama format descriptor
      def self.convert_to_ollama_descriptor(enhanced)
        # Extract when_to_use / when_not_to_use
        when_to_use = enhanced[:when_to_use] || []
        when_not_to_use = enhanced[:when_not_to_use] || []

        # Convert to string if array
        when_to_use = when_to_use.join(". ") if when_to_use.is_a?(Array)
        when_not_to_use = when_not_to_use.join(". ") if when_not_to_use.is_a?(Array)

        Ollama::Agent::ToolDescriptor.new(
          name: enhanced[:name],
          description: enhanced[:description],
          inputs: enhanced[:inputs],
          outputs: enhanced[:outputs],
          when_to_use: when_to_use,
          when_not_to_use: when_not_to_use,
          side_effects: enhanced[:side_effects] || [],
          safety_rules: enhanced[:safety_rules] || [],
          category: enhanced[:category],
          risk_level: enhanced[:risk_level] || :none
        )
      end

      # Get handler for a tool (delegates to DhanTools or creates stub)
      # @param tool_name [String] Tool name
      # @param dhan_client [Object, nil] DhanHQ client
      # @return [Proc] Tool handler
      def self.get_handler_for_tool(tool_name, dhan_client)
        # If DhanHQ::Models is available, use DhanTools handlers (they use Models directly)
        return get_dhan_complete_handler(tool_name) if dhan_configured?

        # Otherwise, create a bridge handler that returns mocks
        create_bridge_handler(tool_name, dhan_client)
      end

      # Check if DhanHQ is configured (Models are accessible)
      # @return [Boolean]
      def self.dhan_configured?
        return false unless defined?(DhanHQ)
        return false unless defined?(DhanHQ::Models)

        # Check if we can access a known model class
        defined?(DhanHQ::Models::Funds) || defined?(DhanHQ::Models::Position) || defined?(DhanHQ::Models::Instrument)
      end

      # Get handler from DhanTools (which uses DhanHQ::Models directly)
      # @param tool_name [String] Tool name
      # @return [Proc, nil] Handler or nil if not found
      def self.get_dhan_complete_handler(tool_name)
        return nil unless defined?(Ollama::Agent::Tools::DhanTools)

        # Create a temporary registry to get the handler from DhanTools
        temp_registry = Ollama::Agent::ToolRegistry.new
        Ollama::Agent::Tools::DhanTools.register_all(
          registry: temp_registry,
          dhan_client: nil # DhanTools uses DhanHQ::Models directly
        )

        # Get the handler from the registry
        tool_entry = temp_registry.instance_variable_get(:@tools)[tool_name]
        tool_entry&.dig(:handler)
      end

      # Create a bridge handler that can call DhanHQ or return mock data
      # @param tool_name [String] Tool name
      # @param dhan_client [Object, nil] DhanHQ client
      # @return [Proc] Handler
      def self.create_bridge_handler(tool_name, dhan_client)
        lambda { |args|
          # Try to call actual DhanHQ if available
          if dhan_client && dhan_client.respond_to?(:call_tool)
            dhan_client.call_tool(tool_name, args)
          else
            # Return mock response for testing
            {
              status: "success",
              tool: tool_name,
              args: args,
              result: mock_tool_response(tool_name, args)
            }
          end
        }
      end

      # Mock tool response for testing
      # @param tool_name [String] Tool name
      # @param args [Hash] Tool arguments
      # @return [Hash] Mock response
      def self.mock_tool_response(tool_name, args)
        case tool_name
        when "dhan.market.ltp"
          { ltp: 100.0, timestamp: Time.now.iso8601 }
        when "dhan.instrument.find"
          { security_id: "12345", instrument_type: "INDEX", symbol: args[:symbol] }
        when "dhan.option.chain"
          { contracts: [], spot_price: 22_450.0 }
        when "dhan.funds.balance"
          { available_margin: 85_000.0, total_margin: 100_000.0 }
        when "dhan.order.place", "dhan.super.place"
          { order_id: "SIMULATED_ORDER", status: "DRY_RUN" }
        else
          { result: "mock_response" }
        end
      end
    end
  end
end
