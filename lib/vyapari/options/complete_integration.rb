# frozen_string_literal: true

# Complete integration example: State machine + Phased agents + Prompts
# Maps directly to Vyapari folder structure

require_relative "trading_state_machine"
require_relative "phased_agent"
require_relative "agent_prompts"
require_relative "../../ollama/agent/tools/dhan_tools"
require_relative "../../ollama/agent/tool_registry"
require_relative "../../ollama/agent/safety_gate"
require_relative "../tools/tool_registry_adapter"
require_relative "../tools/enhanced_dhan_tools"

module Vyapari
  module Options
    # Complete trading system integration
    # Combines state machine, phased agents, and prompts
    class CompleteIntegration
      def self.setup_system(dry_run: true, max_position_size: 10_000)
        # 1. Create state machine
        state_machine = TradingStateMachine.new

        # 2. Create tool registry with enhanced DhanHQ tools
        registry = Ollama::Agent::ToolRegistry.new

        # Register enhanced tools (preferred - has examples and better metadata)
        begin
          Vyapari::Tools::ToolRegistryAdapter.register_enhanced_tools(
            registry: registry,
            dhan_client: nil # Pass actual dhan_client if available
          )
        rescue StandardError => e
          # Fallback to legacy DhanTools if enhanced tools fail
          @logger&.warn("Enhanced tools registration failed, using legacy: #{e.message}")
          Ollama::Agent::Tools::DhanTools.register_all(registry: registry)
        end

        # 3. Create safety gate
        safety_gate = Ollama::Agent::SafetyGate.new(
          rules: Ollama::Agent::SafetyGate.trading_rules(
            max_position_size: max_position_size,
            require_stoploss: true,
            dry_run_only: dry_run
          )
        )

        # 4. Create phased agent (enable test mode only if explicitly requested)
        test_mode = ENV.fetch("VYAPARI_TEST_MODE", "false") == "true"
        phased_agent = PhasedAgent.new(
          registry: registry,
          safety_gate: safety_gate,
          test_mode: test_mode
        )

        {
          state_machine: state_machine,
          phased_agent: phased_agent,
          registry: registry,
          safety_gate: safety_gate
        }
      end

      # Run complete workflow with state machine tracking
      def self.run_complete_workflow(task:, dry_run: true)
        system = setup_system(dry_run: dry_run)
        sm = system[:state_machine]
        agent = system[:phased_agent]

        puts "\n" + TradingStateMachine.diagram
        puts "\n" + "=" * 70
        puts "Starting Complete Options Trading Workflow"
        puts "=" * 70

        # Track state transitions
        sm.transition_to(:market_analysis)
        puts "\n📊 State: #{sm.current_state}"
        puts "   LLM Allowed: #{sm.llm_allowed?}"
        puts "   Max Iterations: #{sm.max_iterations}"

        # Run workflow
        result = agent.run(task)

        # Update state machine based on result
        case result[:final_status]
        when "executed"
          sm.transition_to(:order_execution)
          sm.transition_to(:position_track)
          sm.transition_to(:completed)
        when "no_trade"
          sm.transition_to(:completed)
        when "validation_failed", "execution_failed", "analysis_failed"
          sm.transition_to(:rejected)
        end

        # Display results
        puts "\n" + "=" * 70
        puts "Workflow Complete"
        puts "=" * 70
        puts "Final State: #{sm.current_state}"
        puts "Final Status: #{result[:final_status]}"
        puts "Final Output: #{result[:final_output]}"

        puts "\nState History:"
        sm.state_history.each do |transition|
          puts "  #{transition[:from]} → #{transition[:to]} (#{transition[:timestamp]})"
        end

        puts "\nPhase Results:"
        result[:phases].each do |phase, phase_result|
          next unless phase_result.is_a?(Hash)

          puts "\n  #{phase.to_s.upcase}:"
          puts "    Status: #{phase_result[:status]}" if phase_result[:status]
          if phase_result[:iterations] && phase_result[:max_iterations]
            puts "    Iterations: #{phase_result[:iterations]}/#{phase_result[:max_iterations]}"
          end
          if phase_result[:duration] && phase_result[:duration].respond_to?(:round)
            puts "    Duration: #{phase_result[:duration].round(2)}s"
          end
        end

        # Total LLM calls
        total_llm_calls = result[:phases].sum do |_, pr|
          next 0 unless pr.is_a?(Hash)

          (pr[:iterations] || pr["iterations"] || 0).to_i
        end
        puts "\nTotal LLM Calls: #{total_llm_calls} (max allowed: #{Ollama::Agent::IterationLimits::MAX_LLM_CALLS_PER_TRADE})"

        {
          state_machine: sm,
          result: result,
          total_llm_calls: total_llm_calls
        }
      end

      # Show complete system architecture
      def self.show_architecture
        puts TradingStateMachine.diagram

        puts "\n" + "=" * 70
        puts "State Configurations"
        puts "=" * 70

        TradingStateMachine::STATE_CONFIGS.each do |state, config|
          puts "\n#{state.to_s.upcase}:"
          puts "  LLM Allowed: #{config[:llm_allowed]}"
          puts "  Max Iterations: #{config[:max_iterations]}"
          puts "  Purpose: #{config[:purpose]}"
          puts "  Allowed Tools: #{config[:allowed_tools].join(", ")}" if config[:allowed_tools]
          puts "  Blocked Tools: #{config[:blocked_tools].join(", ")}" if config[:blocked_tools]
        end

        puts "\n" + "=" * 70
        puts "Agent Prompts Available"
        puts "=" * 70
        puts "  Agent A (Analysis): #{AgentPrompts.agent_a_system_prompt.length} chars"
        puts "  Agent B (Validation): #{AgentPrompts.agent_b_system_prompt.length} chars"
        puts "  Agent C (Execution): #{AgentPrompts.agent_c_system_prompt.length} chars"
      end
    end
  end
end

# Uncomment to run examples:
# Vyapari::Options::CompleteIntegration.show_architecture
# Vyapari::Options::CompleteIntegration.run_complete_workflow(task: "Analyze NIFTY options buying")
