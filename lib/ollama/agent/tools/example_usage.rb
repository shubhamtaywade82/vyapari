# frozen_string_literal: true

# Example usage of Ollama Agent with formal tool descriptors
# This demonstrates the Cursor-style tool system

require_relative "../tool_registry"
require_relative "../safety_gate"
require_relative "dhan_tools"

module Ollama
  class Agent
    module Tools
      # Example: How to set up and use the agent with formal tools
      class ExampleUsage
        def self.setup_agent(dhan_client: nil, dry_run: true)
          # 1. Create tool registry
          registry = ToolRegistry.new

          # 2. Register DhanHQ tools
          DhanTools.register_all(registry: registry, dhan_client: dhan_client)

          # 3. Create safety gate with trading rules
          safety_gate = SafetyGate.new(
            rules: SafetyGate.trading_rules(
              max_position_size: 10_000,
              require_stoploss: true,
              dry_run_only: dry_run
            )
          )

          # 4. Create agent with registry and safety gate
          agent = Ollama::Agent.new(
            registry: registry,
            safety_gate: safety_gate,
            max_iterations: 5,
            timeout: 30
          )

          {
            agent: agent,
            registry: registry,
            safety_gate: safety_gate
          }
        end

        # Example: Simple tool call
        def self.example_simple_call
          registry = ToolRegistry.new

          registry.register(
            descriptor: {
              name: "math.add",
              description: "Adds two numbers",
              inputs: {
                type: "object",
                properties: {
                  a: { type: "number" },
                  b: { type: "number" }
                },
                required: ["a", "b"]
              },
              outputs: {
                type: "object",
                properties: {
                  result: { type: "number" }
                }
              }
            },
            handler: ->(args) { { result: (args[:a] || args["a"]) + (args[:b] || args["b"]) } }
          )

          # Execute tool
          result = registry.call("math.add", { a: 5, b: 3 })
          puts "Result: #{result.inspect}"
          result
        end

        # Example: Agent loop with tools
        def self.example_agent_loop
          setup = setup_agent(dry_run: true)
          agent = setup[:agent]

          # Run agent with a task
          result = agent.loop(
            task: "Check current NIFTY price and place a buy order if price is below 24000"
          )

          puts "Agent result: #{result.inspect}"
          result
        end
      end
    end
  end
end

# Uncomment to run examples:
# Ollama::Agent::Tools::ExampleUsage.example_simple_call
# Ollama::Agent::Tools::ExampleUsage.example_agent_loop

