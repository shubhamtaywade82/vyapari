# frozen_string_literal: true

# Example: Using Vyapari phased options trading agent
# Demonstrates the complete workflow

require_relative "phased_agent"
require_relative "state_machine"
require_relative "../../ollama/agent/tools/dhan_tools"
require_relative "../../ollama/agent/tool_registry"
require_relative "../../ollama/agent/safety_gate"

module Vyapari
  module Options
    class PhasedUsageExample
      def self.setup_complete_system
        # 1. Create tool registry with all DhanHQ tools
        registry = Ollama::Agent::ToolRegistry.new
        Ollama::Agent::Tools::DhanTools.register_all(registry: registry)

        # 2. Create safety gate
        safety_gate = Ollama::Agent::SafetyGate.new(
          rules: Ollama::Agent::SafetyGate.trading_rules(
            max_position_size: 10_000,
            require_stoploss: true,
            dry_run_only: true
          )
        )

        # 3. Create phased agent
        phased_agent = PhasedAgent.new(
          client: nil, # Will use default
          registry: registry,
          safety_gate: safety_gate
        )

        {
          phased_agent: phased_agent,
          registry: registry,
          safety_gate: safety_gate
        }
      end

      # Example: Complete options trading workflow
      def self.example_complete_workflow
        setup = setup_complete_system
        agent = setup[:phased_agent]

        puts "\n" + StateMachine.diagram
        puts "\n" + "=" * 60
        puts "Running Complete Options Trading Workflow"
        puts "=" * 60 + "\n"

        # Run complete workflow
        result = agent.run("Analyze NIFTY options buying opportunity")

        puts "\n" + "=" * 60
        puts "Workflow Result"
        puts "=" * 60
        puts "Final Status: #{result[:final_status]}"
        puts "Final State: #{result[:state]}"
        puts "Final Output: #{result[:final_output]}"

        puts "\nPhase Results:"
        result[:phases].each do |phase, phase_result|
          puts "\n  #{phase.to_s.upcase}:"
          puts "    Status: #{phase_result[:status]}"
          puts "    Iterations: #{phase_result[:iterations]}/#{phase_result[:max_iterations]}"
          puts "    Duration: #{phase_result[:duration].round(2)}s"
          puts "    Reason: #{phase_result[:reason][0..100]}..." if phase_result[:reason]
        end

        if result[:trade_plan]
          puts "\nTrade Plan:"
          puts "  Bias: #{result[:trade_plan][:bias]}"
          puts "  Setup: #{result[:trade_plan][:setup]}"
        end

        if result[:executable_plan]
          puts "\nExecutable Plan:"
          exec_plan = result[:executable_plan][:execution_plan] || result[:executable_plan]["execution_plan"]
          if exec_plan
            puts "  Quantity: #{exec_plan[:quantity] || exec_plan["quantity"]}"
            puts "  Entry: #{exec_plan[:entry_price] || exec_plan["entry_price"]}"
            puts "  Stop-Loss: #{exec_plan[:stop_loss] || exec_plan["stop_loss"]}"
            puts "  Target: #{exec_plan[:target] || exec_plan["target"]}"
          end
        end

        puts "\nOrder ID: #{result[:order_id]}" if result[:order_id]

        result
      end

      # Example: Show iteration limits
      def self.example_iteration_limits
        puts "\n" + "=" * 60
        puts "Production-Safe Iteration Limits (Vyapari)"
        puts "=" * 60 + "\n"

        puts "PHASE 1: Market Analysis Agent"
        puts "  Max Iterations: #{Ollama::Agent::IterationLimits::ANALYSIS}"
        puts "  Range: 5-8 iterations"
        puts "  Purpose: Deep reasoning allowed for market analysis"
        puts "  Tools: market data, historical, option chain"
        puts "  Output: TradePlan JSON"

        puts "\nPHASE 2: Plan Validation Agent"
        puts "  Max Iterations: #{Ollama::Agent::IterationLimits::VALIDATION}"
        puts "  Range: 2-3 iterations"
        puts "  Purpose: Quick risk checks (reject fast if uncertain)"
        puts "  Tools: funds, positions, risk checks"
        puts "  Output: APPROVED / REJECTED"

        puts "\nPHASE 3: Order Execution Agent"
        puts "  Max Iterations: #{Ollama::Agent::IterationLimits::TRADING_EXECUTION}"
        puts "  Range: 1-2 iterations"
        puts "  Purpose: Fast execution (nearly dumb, just execute)"
        puts "  Tools: super_order, order.place"
        puts "  Output: order_id"

        puts "\nPHASE 4: Position Tracking"
        puts "  Max Iterations: 0 (NO LLM)"
        puts "  Purpose: WebSocket-driven deterministic rules"
        puts "  Tools: WebSocket ticks only"
        puts "  Output: Exit signal"

        puts "\n" + "=" * 60
        puts "HARD GLOBAL LIMIT"
        puts "=" * 60
        puts "One trade = max #{Ollama::Agent::IterationLimits::MAX_LLM_CALLS_PER_TRADE} LLM calls total"
        puts "Typical: 6-8 (analysis) + 2 (validation) + 1 (execution) = 9-11 calls"
        puts "Maximum: 8 (analysis) + 3 (validation) + 2 (execution) = 13 calls"
      end

      # Example: State machine visualization
      def self.example_state_machine
        puts StateMachine.diagram

        puts "\n" + "=" * 60
        puts "State Transitions"
        puts "=" * 60

        StateMachine::TRANSITIONS.each do |from, to_states|
          puts "\n#{from.to_s.upcase} →"
          to_states.each do |to|
            puts "  → #{to.to_s.upcase}"
          end
        end

        puts "\n" + "=" * 60
        puts "Agent Configurations"
        puts "=" * 60

        StateMachine::AGENT_MAPPING.each do |state, config|
          puts "\n#{state.to_s.upcase}:"
          puts "  Agent: #{config[:agent]}"
          puts "  Max Iterations: #{config[:max_iterations]}"
          puts "  LLM Allowed: #{config[:llm_allowed]}"
          puts "  Tools: #{config[:tools].join(", ")}"
          puts "  Output: #{config[:output]}"
        end
      end
    end
  end
end

# Uncomment to run examples:
# Vyapari::Options::PhasedUsageExample.example_iteration_limits
# Vyapari::Options::PhasedUsageExample.example_state_machine
# Vyapari::Options::PhasedUsageExample.example_complete_workflow
