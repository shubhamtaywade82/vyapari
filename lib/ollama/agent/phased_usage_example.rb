# frozen_string_literal: true

# Example: Phase-based multi-agent trading system
# Demonstrates proper iteration limits and phase separation

require_relative "phased_agent"
require_relative "iteration_limits"
require_relative "../tools/dhan_complete"
require_relative "../tool_registry"
require_relative "../safety_gate"

module Ollama
  class Agent
    class PhasedUsageExample
      def self.setup_complete_system
        # 1. Create tool registry with all DhanHQ tools
        registry = ToolRegistry.new
        Tools::DhanComplete.register_all(registry: registry)

        # 2. Create safety gate
        safety_gate = SafetyGate.new(
          rules: SafetyGate.trading_rules(
            max_position_size: 10_000,
            require_stoploss: true,
            dry_run_only: true
          )
        )

        # 3. Create phased agent
        phased_agent = PhasedAgent.new(
          client: Ollama::Client.new,
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
      def self.example_options_workflow
        setup = setup_complete_system
        agent = setup[:phased_agent]

        # Run complete workflow through phases
        result = agent.run(
          workflow: :options_trading,
          task: "Analyze NIFTY and execute trade if conditions are met"
        )

        puts "Workflow Result:"
        puts "  Status: #{result[:final_status]}"
        puts "  Output: #{result[:final_output]}"
        puts "\nPhase Results:"
        result[:phases].each do |phase, phase_result|
          puts "  #{phase}:"
          puts "    Status: #{phase_result[:status]}"
          puts "    Iterations: #{phase_result[:iterations]}/#{phase_result[:max_iterations]}"
          puts "    Duration: #{phase_result[:duration].round(2)}s"
        end

        result
      end

      # Example: Show iteration limits
      def self.example_iteration_limits
        puts "Production-Safe Iteration Limits:"
        puts "\nAnalysis Agents:"
        puts "  Analysis: #{IterationLimits::ANALYSIS}"
        puts "  Planning: #{IterationLimits::PLANNING}"
        puts "  Research: #{IterationLimits::RESEARCH}"

        puts "\nValidation Agents:"
        puts "  Validation: #{IterationLimits::VALIDATION}"
        puts "  Risk Check: #{IterationLimits::RISK_CHECK}"

        puts "\nExecution Agents:"
        puts "  Execution: #{IterationLimits::EXECUTION}"
        puts "  Trading Execution: #{IterationLimits::TRADING_EXECUTION} (≤3 for safety)"

        puts "\nMonitoring Agents:"
        puts "  Monitoring: #{IterationLimits::MONITORING}"
        puts "  Status Check: #{IterationLimits::STATUS_CHECK}"

        puts "\nDevelopment Agents:"
        puts "  Debug: #{IterationLimits::DEBUG}"
        puts "  Cursor-like: #{IterationLimits::CURSOR_LIKE} (file editing, not trading)"
      end

      # Example: Single phase execution
      def self.example_single_phase
        setup = setup_complete_system
        agent = setup[:phased_agent]

        # Run only analysis phase
        result = agent.send(:run_phase,
          phase: :analysis,
          task: "Analyze NIFTY option chain and produce trade plan",
          allowed_tools: agent.send(:analysis_tools),
          max_iterations: IterationLimits::ANALYSIS
        )

        puts "Analysis Phase Result:"
        puts "  Status: #{result[:status]}"
        puts "  Iterations: #{result[:iterations]}/#{result[:max_iterations]}"
        puts "  Reason: #{result[:reason]}"

        result
      end
    end
  end
end

# Uncomment to run examples:
# Ollama::Agent::PhasedUsageExample.example_iteration_limits
# Ollama::Agent::PhasedUsageExample.example_single_phase
# Ollama::Agent::PhasedUsageExample.example_options_workflow

