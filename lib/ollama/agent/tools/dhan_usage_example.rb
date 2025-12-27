# frozen_string_literal: true

# Example: Complete DhanHQ toolset usage
# This demonstrates how to set up and use the production-grade toolset

require_relative "../tool_registry"
require_relative "../safety_gate"
require_relative "dhan_tools"

module Ollama
  class Agent
    module Tools
      class DhanUsageExample
        # Complete setup with all tools and safety gates
        def self.setup_complete_agent(dry_run: true, max_position_size: 10_000)
          # 1. Create tool registry
          registry = ToolRegistry.new

          # 2. Register ALL DhanHQ tools
          # Note: cache_store would be your WebSocket cache implementation
          DhanTools.register_all(
            registry: registry,
            dhan_client: nil, # Will use DhanHQ::Models directly
            cache_store: nil  # Optional: WebSocket cache
          )

          # 3. Create safety gate with trading rules
          safety_gate = SafetyGate.new(
            rules: SafetyGate.trading_rules(
              max_position_size: max_position_size,
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

        # Example: Market data workflow
        def self.example_market_data_workflow
          registry = ToolRegistry.new
          DhanTools.register_market_data_tools(registry, nil)

          # Find instrument
          result = registry.call("dhan.instrument.find", {
            exchange_segment: "IDX_I",
            symbol: "NIFTY"
          })
          puts "Instrument: #{result.inspect}"

          # Get LTP
          if result[:status] == "success" && result[:result][:security_id]
            ltp_result = registry.call("dhan.market.ltp", {
              exchange_segment: "IDX_I",
              security_id: result[:result][:security_id]
            })
            puts "LTP: #{ltp_result.inspect}"
          end
        end

        # Example: Options trading workflow
        def self.example_options_workflow
          registry = ToolRegistry.new
          DhanTools.register_all(registry: registry)

          # 1. Get expiries
          expiries = registry.call("dhan.option.expiries", {
            underlying_scrip: "NIFTY",
            underlying_seg: "IDX_I"
          })
          puts "Expiries: #{expiries.inspect}"

          # 2. Get option chain
          if expiries[:status] == "success" && expiries[:result].any?
            chain = registry.call("dhan.option.chain", {
              underlying_scrip: "NIFTY",
              underlying_seg: "IDX_I",
              expiry: expiries[:result].first
            })
            puts "Option Chain: #{chain.inspect}"
          end
        end

        # Example: Trading workflow with safety
        def self.example_trading_workflow
          setup = setup_complete_agent(dry_run: true)
          agent = setup[:agent]

          # Run agent with trading task
          result = agent.loop(
            task: <<~TASK
              Check NIFTY current price.
              If price is below 24000, place a Super Order to buy NIFTY 24500 CE with:
              - Stop-loss at 65% of premium
              - Target at 140% of premium
              - Verify funds before placing order
            TASK
          )

          puts "Agent result: #{result.inspect}"
          result
        end

        # Example: Account state check
        def self.example_account_check
          registry = ToolRegistry.new
          DhanTools.register_account_tools(registry, nil)

          # Check funds
          funds = registry.call("dhan.funds.balance", {})
          puts "Funds: #{funds.inspect}"

          # Check positions
          positions = registry.call("dhan.positions.list", {})
          puts "Positions: #{positions.inspect}"

          # Check orders
          orders = registry.call("dhan.orders.list", {})
          puts "Orders: #{orders.inspect}"
        end
      end
    end
  end
end

# Uncomment to run examples:
# Ollama::Agent::Tools::DhanUsageExample.example_market_data_workflow
# Ollama::Agent::Tools::DhanUsageExample.example_options_workflow
# Ollama::Agent::Tools::DhanUsageExample.example_trading_workflow
# Ollama::Agent::Tools::DhanUsageExample.example_account_check

