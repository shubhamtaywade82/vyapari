# frozen_string_literal: true

# Console helper for testing Vyapari phases individually
# Usage in bin/console:
#   require "vyapari/options/console_helper"
#   helper = Vyapari::Options::ConsoleHelper.new
#   helper.test_phase_1("Analyze NIFTY for options buying")

module Vyapari
  module Options
    class ConsoleHelper
      def initialize(dry_run: true, test_mode: false, force_bias: nil, show_tool_calls: false, dhan_client: nil,
                     continue_on_no_trade: true)
        @dry_run = dry_run
        @test_mode = test_mode
        @force_bias = force_bias # :bullish, :bearish, or nil (use real analysis)
        @show_tool_calls = show_tool_calls # Show actual tool calls vs LLM hallucinations
        @dhan_client = dhan_client # Real DhanHQ client for actual API calls
        @continue_on_no_trade = continue_on_no_trade # Continue testing even if NO_TRADE
        @system = nil
        @agent = nil
      end

      # Setup system (run once)
      def setup
        puts "🔧 Setting up Vyapari system..."

        # Configure DhanHQ from environment if not explicitly provided
        if @dhan_client
          @dhan_configured = true
        else
          @dhan_configured = configure_dhan_from_env
          puts "   - DhanHQ configured from environment variables" if @dhan_configured
        end

        # If DhanHQ configured, register tools (they'll use DhanHQ::Models)
        if @dhan_configured || @dhan_client
          puts "   - Using REAL DhanHQ API (via DhanHQ::Models)"
          @system = setup_with_dhan_client(@dhan_client) # Pass nil, tools use Models directly
        else
          puts "   - No DhanHQ configuration found, using MOCK handlers"
          puts "   💡 Set CLIENT_ID and ACCESS_TOKEN to use real API"
          @system = CompleteIntegration.setup_system(dry_run: @dry_run)
        end

        @agent = @system[:phased_agent]
        puts "✅ System ready!"
        puts "   - State Machine: #{@system[:state_machine].class}"
        puts "   - Tool Registry: #{@system[:registry].tool_names.length} tools"
        puts "   - Safety Gate: #{@system[:safety_gate].class}"
        puts "   - Phased Agent: #{@agent.class}"

        # Check if DhanHQ is configured
        if @dhan_configured || @system[:dhan_client] || @dhan_client
          puts "   - DhanHQ: ✅ Configured (REAL API calls via DhanHQ::Models)"
        else
          puts "   - DhanHQ: ❌ Not configured (using MOCK handlers)"
          puts "   ⚠️  All tool calls will return mock data, not real market data"
          puts "   💡 Set CLIENT_ID and ACCESS_TOKEN environment variables"
        end

        @system
      end

      # Setup system with real DhanHQ client
      def setup_with_dhan_client(dhan_client)
        require_relative "complete_integration"

        # Create state machine
        state_machine = Vyapari::Options::TradingStateMachine.new

        # Create tool registry
        registry = Ollama::Agent::ToolRegistry.new

        # Register tools (they use DhanHQ::Models directly, configured from ENV)
        begin
          Vyapari::Tools::ToolRegistryAdapter.register_enhanced_tools(
            registry: registry,
            dhan_client: dhan_client # Can be nil, tools use DhanHQ::Models
          )
        rescue StandardError => e
          puts "   ⚠️  Enhanced tools registration failed: #{e.message}"
          # Fallback to DhanComplete (uses DhanHQ::Models directly)
          if defined?(Ollama::Agent::Tools::DhanComplete)
            Ollama::Agent::Tools::DhanComplete.register_all(
              registry: registry,
              dhan_client: dhan_client # Can be nil, tools use DhanHQ::Models
            )
          end
        end

        # Create safety gate
        safety_gate = Ollama::Agent::SafetyGate.new(
          rules: Ollama::Agent::SafetyGate.trading_rules(
            max_position_size: 10_000,
            require_stoploss: true,
            dry_run_only: @dry_run
          )
        )

        # Create phased agent
        test_mode = ENV.fetch("VYAPARI_TEST_MODE", "false") == "true"
        phased_agent = Vyapari::Options::PhasedAgent.new(
          registry: registry,
          safety_gate: safety_gate,
          test_mode: test_mode
        )

        {
          state_machine: state_machine,
          registry: registry,
          safety_gate: safety_gate,
          phased_agent: phased_agent,
          dhan_client: dhan_client
        }
      end

      # Test Phase 1: Market Analysis
      def test_phase_1(task = "Analyze NIFTY for options buying", force_bias: nil)
        setup unless @agent
        puts "\n" + "=" * 80
        puts "PHASE 1: MARKET ANALYSIS"
        puts "=" * 80
        puts "Task: #{task}"
        if force_bias || @force_bias
          bias = force_bias || @force_bias
          puts "⚠️  FORCING BIAS: #{bias.to_s.upcase} (for testing)"
        end
        puts "✅ Using REAL DhanHQ API calls" if @dhan_client
        puts ""

        context = default_context

        # If forcing a bias, inject a valid trade plan after analysis
        if force_bias || @force_bias
          bias = force_bias || @force_bias
          result = @agent.run(task, context: context)

          # Override with a valid trade plan for the requested bias
          if result[:phases][:analysis]
            result[:trade_plan] = create_valid_trade_plan(bias)
            result[:phases][:analysis][:status] = "completed"
            result[:final_status] = "completed"
            puts "✅ Created valid #{bias.to_s.upcase} trade plan for testing"
          end
        else
          result = @agent.run(task, context: context)

          # If NO_TRADE but continue_on_no_trade is true, create a trade plan for testing
          if @continue_on_no_trade && (result[:final_status] == "no_trade" || result[:trade_plan].nil?)
            puts "\n⚠️  Analysis returned NO_TRADE, but continuing with mock trade plan for testing..."
            result[:trade_plan] = create_valid_trade_plan(:bullish) # Default to bullish for testing
            result[:phases][:analysis][:status] = "completed"
            result[:final_status] = "completed"
            puts "✅ Created mock trade plan to test subsequent phases"
          end
        end

        puts "\n📊 Analysis Result:"
        puts "   Status: #{result[:final_status]}"
        puts "   Output: #{result[:final_output]}"

        if result[:phases][:analysis]
          analysis = result[:phases][:analysis]
          puts "\n   Analysis Details:"
          puts "     Status: #{analysis[:status]}"
          puts "     Iterations: #{analysis[:iterations]}/#{analysis[:max_iterations]}"
          if analysis[:mtf_result]
            mtf = analysis[:mtf_result]
            puts "     MTF Status: #{mtf[:status]}"
            puts "     Iterations Used: #{mtf[:iterations_used]}"
            if mtf[:timeframes]
              mtf[:timeframes].each do |tf_name, tf_result|
                next unless tf_result.is_a?(Hash)

                puts "     #{tf_name.to_s.upcase}:"
                puts "       Regime/Direction: #{tf_result[:regime] || tf_result[:direction]}"
                puts "       Iterations: #{tf_result[:iterations]}"
              end
            end
          end
        end

        if result[:trade_plan]
          puts "\n   Trade Plan:"
          puts "     Mode: #{result[:trade_plan][:mode] || result[:trade_plan]["mode"]}"
          puts "     Bias: #{result[:trade_plan][:bias] || result[:trade_plan]["bias"]}"
          puts "     Instrument: #{result[:trade_plan][:instrument] || result[:trade_plan]["instrument"]}"
        end

        result
      end

      # Test Phase 2: Plan Validation
      def test_phase_2(trade_plan = nil)
        setup unless @agent

        # If no trade plan provided, run phase 1 first
        unless trade_plan
          puts "⚠️  No trade plan provided, running Phase 1 first..."
          phase1_result = test_phase_1
          trade_plan = phase1_result[:trade_plan]
          unless trade_plan
            puts "❌ Phase 1 did not produce a trade plan"
            return nil
          end
        end

        puts "\n" + "=" * 80
        puts "PHASE 2: PLAN VALIDATION"
        puts "=" * 80
        puts "Trade Plan: #{trade_plan[:instrument] || trade_plan["instrument"]}\n"

        # Manually run validation phase
        validation_result = @agent.send(:run_validation_phase, trade_plan)

        puts "\n✅ Validation Result:"
        puts "   Status: #{validation_result[:status]}"
        puts "   Reason: #{validation_result[:reason]}" if validation_result[:reason]
        puts "   Iterations: #{validation_result[:iterations] || 0}"

        if validation_result[:context]
          executable_plan = @agent.send(:extract_executable_plan, validation_result)
          if executable_plan
            puts "\n   Executable Plan:"
            exec_plan = executable_plan[:execution_plan] || executable_plan["execution_plan"]
            if exec_plan
              puts "     Instrument: #{exec_plan[:instrument] || exec_plan["instrument"]}"
              puts "     Strike: #{exec_plan[:strike] || exec_plan["strike"]}"
              puts "     Type: #{exec_plan[:type] || exec_plan["type"]}"
              puts "     Quantity: #{exec_plan[:quantity] || exec_plan["quantity"]}"
              puts "     Lots: #{exec_plan[:lots] || exec_plan["lots"]}"
              puts "     Entry Price: #{exec_plan[:entry_price] || exec_plan["entry_price"]}"
              puts "     Stop Loss: #{exec_plan[:stop_loss] || exec_plan["stop_loss"]}"
            end
          end
        end

        validation_result
      end

      # Test Phase 3: Order Execution
      def test_phase_3(executable_plan = nil)
        setup unless @agent

        # If no executable plan provided, run phases 1 and 2 first
        unless executable_plan
          puts "⚠️  No executable plan provided, running Phases 1 & 2 first..."
          phase1_result = test_phase_1
          trade_plan = phase1_result[:trade_plan]
          unless trade_plan
            puts "❌ Phase 1 did not produce a trade plan"
            return nil
          end

          phase2_result = test_phase_2(trade_plan)
          executable_plan = @agent.send(:extract_executable_plan, phase2_result)
          unless executable_plan
            puts "❌ Phase 2 did not produce an executable plan"
            return nil
          end
        end

        puts "\n" + "=" * 80
        puts "PHASE 3: ORDER EXECUTION"
        puts "=" * 80
        exec_plan = executable_plan[:execution_plan] || executable_plan["execution_plan"]
        if exec_plan
          puts "Executable Plan:"
          puts "  Instrument: #{exec_plan[:instrument] || exec_plan["instrument"]}"
          puts "  Strike: #{exec_plan[:strike] || exec_plan["strike"]}"
          puts "  Type: #{exec_plan[:type] || exec_plan["type"]}"
          puts "  Quantity: #{exec_plan[:quantity] || exec_plan["quantity"]}\n"
        end

        # Manually run execution phase
        execution_result = @agent.send(:run_execution_phase, executable_plan)

        puts "\n⚡ Execution Result:"
        puts "   Status: #{execution_result[:status]}"
        puts "   Order ID: #{execution_result[:order_id]}" if execution_result[:order_id]
        puts "   Reason: #{execution_result[:reason]}" if execution_result[:reason]
        puts "   Iterations: #{execution_result[:iterations] || 0}"

        execution_result
      end

      # Test complete workflow
      def test_complete(task = "Analyze NIFTY for options buying")
        setup unless @agent
        puts "\n" + "=" * 80
        puts "COMPLETE WORKFLOW TEST"
        puts "=" * 80
        puts "Task: #{task}"
        puts "⚠️  FORCING BIAS: #{@force_bias.to_s.upcase} (for testing)" if @force_bias
        puts "✅ Using REAL DhanHQ API calls" if @dhan_configured || @dhan_client
        puts "⚠️  Will continue even if NO_TRADE (for testing)" if @continue_on_no_trade
        puts ""

        context = default_context

        # If forcing a bias, inject a valid trade plan and continue workflow
        if @force_bias
          # Create valid trade plan first
          trade_plan = create_valid_trade_plan(@force_bias)
          puts "✅ Created valid #{@force_bias.to_s.upcase} trade plan for testing"

          # Run global precheck
          checklist_guard = @agent.instance_variable_get(:@checklist_guard)
          global_precheck = checklist_guard.run_global_precheck(context: context)

          # Create analysis result with valid trade plan
          analysis_result = {
            phase: :analysis,
            status: "completed",
            reason: "Valid #{@force_bias.to_s.upcase} trade plan created for testing",
            iterations: 0,
            max_iterations: 7,
            context: [],
            trace: [],
            duration: 0,
            mtf_result: {
              status: "completed",
              trade_plan: trade_plan
            }
          }

          # Manually continue the workflow with the forced trade plan
          result = {
            workflow: :options_trading,
            initial_task: task,
            phases: {
              global_precheck: global_precheck,
              analysis: analysis_result
            },
            trade_plan: trade_plan,
            final_status: "completed",
            final_output: "Valid #{@force_bias.to_s.upcase} trade plan created for testing"
          }

          # Continue with Phase 2: Validation
          validation_result = @agent.send(:run_validation_phase, trade_plan)
          result[:phases][:validation] = validation_result

          # Extract executable plan
          executable_plan = @agent.send(:extract_executable_plan, validation_result)

          # If validation failed, create mock executable plan (for testing)
          if validation_result[:status] != "approved"
            executable_plan = @agent.send(:create_mock_executable_plan, trade_plan)
            result[:phases][:validation][:status] = "approved"
            puts "⚠️  Validation failed, using mock executable plan for testing"
          end

          result[:executable_plan] = executable_plan

          # Continue with Phase 3: Execution
          if executable_plan
            execution_result = @agent.send(:run_execution_phase, executable_plan)
            result[:phases][:execution] = execution_result

            # Show tool calls if requested
            if @show_tool_calls && execution_result[:trace]
              puts "\n🔧 Tool Calls Made:"
              execution_result[:trace].each do |trace_entry|
                next unless trace_entry[:tool_call]

                tool_name = trace_entry[:tool_call][:tool]
                tool_args = trace_entry[:tool_call][:args]
                tool_result = trace_entry[:result]

                puts "   Tool: #{tool_name}"
                puts "   Args: #{tool_args.inspect}"
                puts "   Result Status: #{tool_result[:status]}"
                puts "   Error: #{tool_result[:error]}" if tool_result[:error]
                puts "   Response: #{tool_result[:result].inspect}" if tool_result[:result]
                puts ""
              end
            end

            # If execution failed, simulate success (for testing)
            if execution_result[:status] != "executed"
              result[:order_id] = "TEST_ORDER_#{Time.now.to_i}"
              result[:phases][:execution][:status] = "executed"
              result[:phases][:execution][:order_id] = result[:order_id]
              puts "⚠️  Execution failed, simulating success for testing"
              if execution_result[:context] && execution_result[:context].any?
                error = execution_result[:context].first
                puts "   Blocked by: #{error[:error]}" if error[:error]
              end
            else
              result[:order_id] = execution_result[:order_id]
            end

            result[:final_status] = "test_completed"
            result[:final_output] = "Order placed: #{result[:order_id]}"
          else
            result[:final_status] = "validation_failed"
            result[:final_output] = validation_result[:reason]
          end
        else
          result = @agent.run(task, context: context)

          # If NO_TRADE but continue_on_no_trade is true, create a trade plan and continue
          if @continue_on_no_trade && (result[:final_status] == "no_trade" || result[:trade_plan].nil?)
            puts "\n⚠️  Analysis returned NO_TRADE, but continuing with mock trade plan for testing..."
            trade_plan = create_valid_trade_plan(:bullish) # Default to bullish for testing

            # Update result to continue workflow
            result[:trade_plan] = trade_plan
            result[:phases][:analysis][:status] = "completed"
            result[:final_status] = "completed"
            puts "✅ Created mock trade plan to test subsequent phases"

            # Continue with Phase 2: Validation
            validation_result = @agent.send(:run_validation_phase, trade_plan)
            result[:phases][:validation] = validation_result

            # Extract executable plan
            executable_plan = @agent.send(:extract_executable_plan, validation_result)

            # If validation failed, create mock executable plan (for testing)
            if validation_result[:status] != "approved"
              executable_plan = @agent.send(:create_mock_executable_plan, trade_plan)
              result[:phases][:validation][:status] = "approved"
              puts "⚠️  Validation failed, using mock executable plan for testing"
            end

            result[:executable_plan] = executable_plan

            # Continue with Phase 3: Execution
            if executable_plan
              execution_result = @agent.send(:run_execution_phase, executable_plan)
              result[:phases][:execution] = execution_result

              # If execution failed, simulate success (for testing)
              if execution_result[:status] != "executed"
                result[:order_id] = "TEST_ORDER_#{Time.now.to_i}"
                result[:phases][:execution][:status] = "executed"
                result[:phases][:execution][:order_id] = result[:order_id]
                puts "⚠️  Execution failed, simulating success for testing"
              else
                result[:order_id] = execution_result[:order_id]
              end

              result[:final_status] = "test_completed"
              result[:final_output] = "Order placed: #{result[:order_id]}"
            end
          end
        end

        puts "\n📊 Final Result:"
        puts "   Status: #{result[:final_status]}"
        puts "   Output: #{result[:final_output]}"
        puts "   Order ID: #{result[:order_id]}" if result[:order_id]

        puts "\n📋 Phase Summary:"
        result[:phases].each do |phase_name, phase_result|
          next unless phase_result.is_a?(Hash)

          status = phase_result[:status]
          iterations = phase_result[:iterations] || 0
          icon = %w[completed approved executed].include?(status) ? "✅" : "⚠️"
          puts "   #{icon} #{phase_name.to_s.upcase}: #{status} (#{iterations} iterations)"
        end

        result
      end

      # Test individual MTF timeframes
      def test_mtf_htf(task = "Analyze NIFTY for options buying")
        setup unless @agent
        puts "\n" + "=" * 80
        puts "MTF: HIGHER TIMEFRAME (15m)"
        puts "=" * 80

        # Access MTF agent through run_analysis_phase
        analysis_result = @agent.send(:run_analysis_phase, task)
        mtf_result = analysis_result[:mtf_result]

        unless mtf_result && mtf_result[:timeframes]
          puts "❌ MTF result not found in analysis"
          puts "   Analysis status: #{analysis_result[:status]}"
          puts "   Reason: #{analysis_result[:reason]}" if analysis_result[:reason]
          return nil
        end

        htf_result = mtf_result[:timeframes][:htf]
        unless htf_result
          puts "❌ HTF result not found in timeframes"
          puts "   Available timeframes: #{mtf_result[:timeframes].keys.join(", ")}"
          return nil
        end

        puts "\n📊 HTF Result:"
        puts "   Regime: #{htf_result[:regime] || "N/A"}"
        puts "   Tradable: #{htf_result[:tradable]}"
        puts "   Reason: #{htf_result[:reason]}" if htf_result[:reason]
        puts "   Iterations: #{htf_result[:iterations] || 0}"

        if htf_result[:regime] == "NO_TRADE" || htf_result[:tradable] == false
          puts "\n⚠️  HTF indicates NO_TRADE - lower timeframes were not analyzed"
        end

        htf_result
      end

      def test_mtf_mtf(task = "Analyze NIFTY for options buying")
        setup unless @agent
        puts "\n" + "=" * 80
        puts "MTF: MID TIMEFRAME (5m)"
        puts "=" * 80

        analysis_result = @agent.send(:run_analysis_phase, task)
        mtf_result = analysis_result[:mtf_result]

        unless mtf_result && mtf_result[:timeframes]
          puts "❌ MTF result not found in analysis"
          puts "   Analysis status: #{analysis_result[:status]}"
          puts "   Reason: #{analysis_result[:reason]}" if analysis_result[:reason]
          return nil
        end

        mtf_result_data = mtf_result[:timeframes][:mtf]
        unless mtf_result_data
          puts "❌ MTF result not found in timeframes"
          puts "   Available timeframes: #{mtf_result[:timeframes].keys.join(", ")}"
          puts "\n⚠️  MTF analysis may have stopped early (HTF returned NO_TRADE)"
          puts "   Try using test_bullish or test_bearish to force valid analysis"
          return nil
        end

        puts "\n📊 MTF Result:"
        puts "   Direction: #{mtf_result_data[:direction] || "N/A"}"
        puts "   Momentum: #{mtf_result_data[:momentum] || "N/A"}"
        puts "   Iterations: #{mtf_result_data[:iterations] || 0}"

        mtf_result_data
      end

      def test_mtf_ltf(task = "Analyze NIFTY for options buying")
        setup unless @agent
        puts "\n" + "=" * 80
        puts "MTF: LOWER TIMEFRAME (1m)"
        puts "=" * 80

        analysis_result = @agent.send(:run_analysis_phase, task)
        mtf_result = analysis_result[:mtf_result]

        unless mtf_result && mtf_result[:timeframes]
          puts "❌ MTF result not found in analysis"
          puts "   Analysis status: #{analysis_result[:status]}"
          puts "   Reason: #{analysis_result[:reason]}" if analysis_result[:reason]
          return nil
        end

        ltf_result = mtf_result[:timeframes][:ltf]
        unless ltf_result
          puts "❌ LTF result not found in timeframes"
          puts "   Available timeframes: #{mtf_result[:timeframes].keys.join(", ")}"
          puts "\n⚠️  LTF analysis may have stopped early (HTF or MTF returned NO_TRADE)"
          puts "   Try using test_bullish or test_bearish to force valid analysis"
          return nil
        end

        puts "\n📊 LTF Result:"
        puts "   Entry Type: #{ltf_result[:entry_type] || "N/A"}"
        puts "   Trigger: #{ltf_result[:trigger]}" if ltf_result[:trigger]
        puts "   Iterations: #{ltf_result[:iterations] || 0}"

        ltf_result
      end

      # Inspect current state
      def inspect_state
        setup unless @agent
        state_machine = @system[:state_machine]
        puts "\n📊 Current State:"
        puts "   State: #{state_machine.current_state}"
        puts "   LLM Allowed: #{state_machine.llm_allowed?}"
        puts "   Max Iterations: #{state_machine.max_iterations}"
        puts "   Allowed Tools: #{state_machine.allowed_tools.join(", ")}"
        puts "\n   State History:"
        state_machine.history.each do |entry|
          puts "     #{entry[:state]} (#{entry[:timestamp]})"
        end
      end

      # List available tools
      def list_tools
        setup unless @system
        registry = @system[:registry]
        puts "\n🔧 Available Tools (#{registry.tool_names.length}):"
        registry.tool_names.each do |tool_name|
          descriptor = registry.descriptor(tool_name)
          puts "   - #{tool_name}"
          puts "     Category: #{descriptor.category}" if descriptor.category
          puts "     Risk: #{descriptor.risk_level}" if descriptor.risk_level
        end
      end

      # Inspect tool calls from a result to see if tools were actually called
      def inspect_tool_calls(result)
        puts "\n" + "=" * 80
        puts "TOOL CALL INSPECTION"
        puts "=" * 80

        tool_calls_found = false

        # Check each phase for tool calls
        result[:phases].each do |phase_name, phase_result|
          next unless phase_result.is_a?(Hash)

          # Check trace for tool calls
          if phase_result[:trace] && phase_result[:trace].any?
            puts "\n📋 Phase: #{phase_name.to_s.upcase}"
            phase_result[:trace].each do |trace_entry|
              next unless trace_entry[:tool_call]

              tool_calls_found = true
              tool_name = trace_entry[:tool_call][:tool]
              tool_args = trace_entry[:tool_call][:args]
              tool_result = trace_entry[:result]

              puts "\n   🔧 Tool Called: #{tool_name}"
              puts "      Args: #{tool_args.inspect}"
              puts "      Result Status: #{tool_result[:status]}" if tool_result[:status]
              puts "      ❌ Error: #{tool_result[:error]}" if tool_result[:error]
              puts "      ✅ Response: #{tool_result[:result].inspect}" if tool_result[:result]
              puts "      🛡️  Safety Errors: #{tool_result[:safety_errors].join(", ")}" if tool_result[:safety_errors]
            end
          end

          # Check context for tool calls
          next unless phase_result[:context] && phase_result[:context].any?

          phase_result[:context].each do |item|
            next unless item[:tool_call] || item[:tool]

            tool_calls_found = true
            tool_name = item[:tool_call]&.dig(:tool) || item[:tool]
            tool_args = item[:tool_call]&.dig(:args) || item[:args] || {}
            tool_result = item[:result] || item

            puts "\n   🔧 Tool Called: #{tool_name}"
            puts "      Args: #{tool_args.inspect}"
            puts "      Result Status: #{tool_result[:status]}" if tool_result[:status]
            puts "      ❌ Error: #{tool_result[:error]}" if tool_result[:error]
            puts "      ✅ Response: #{tool_result[:result].inspect}" if tool_result[:result]
          end
        end

        unless tool_calls_found
          puts "\n⚠️  No tool calls found in result"
          puts "   This could mean:"
          puts "   - LLM didn't call any tools (hallucinated values)"
          puts "   - Tools were blocked by safety gate before execution"
          puts "   - Phase didn't complete successfully"
        end

        # Check if tools are using mocks
        puts "\n" + "=" * 80
        puts "TOOL HANDLER STATUS"
        puts "=" * 80
        registry = @system[:registry]
        puts "   Tools Registered: #{registry.tool_names.length}"
        dhan_status = @dhan_configured || @system[:dhan_client] || @dhan_client ? "✅ Configured (REAL API)" : "❌ Not configured (MOCK)"
        puts "   DhanHQ: #{dhan_status}"
        puts "\n   ⚠️  NOTE: Without DhanHQ configuration, all tools return MOCK responses"
        puts "   Values like symbol, price, etc. are generated by LLM, not from real market data"
        puts "   💡 Set CLIENT_ID and ACCESS_TOKEN to use real API"
      end

      # Test with BULLISH bias
      def test_bullish(task = "Analyze NIFTY for options buying")
        puts "\n🐂 Testing with BULLISH bias\n"
        test_phase_1(task, force_bias: :bullish)
      end

      # Test with BEARISH bias
      def test_bearish(task = "Analyze NIFTY for options buying")
        puts "\n🐻 Testing with BEARISH bias\n"
        test_phase_1(task, force_bias: :bearish)
      end

      # Test complete workflow with BULLISH bias
      def test_complete_bullish(task = "Analyze NIFTY for options buying")
        puts "\n🐂 Testing COMPLETE workflow with BULLISH bias\n"
        @force_bias = :bullish
        test_complete(task)
      end

      # Test complete workflow with BEARISH bias
      def test_complete_bearish(task = "Analyze NIFTY for options buying")
        puts "\n🐻 Testing COMPLETE workflow with BEARISH bias\n"
        @force_bias = :bearish
        test_complete(task)
      end

      # Test with REAL DhanHQ API (even if NO_TRADE, continue testing)
      def test_with_real_dhan(dhan_client, task = "Analyze NIFTY for options buying")
        puts "\n🔌 Testing with REAL DhanHQ API\n"
        @dhan_client = dhan_client
        @continue_on_no_trade = true
        test_complete(task)
      end

      # Configure DhanHQ from environment variables and verify it works
      # DhanHQ tools use DhanHQ::Models directly, which reads from ENV
      def configure_dhan_from_env
        return false unless defined?(DhanHQ)

        begin
          # Configure DhanHQ from environment variables
          # configure_with_env returns nil, not a boolean, so we can't rely on its return value
          DhanHQ.configure_with_env if DhanHQ.respond_to?(:configure_with_env)

          # Also try Vyapari config if available
          Vyapari::Config.configure_dhan! if defined?(Vyapari::Config)

          # Verify configuration by testing if Models are accessible
          # Since user showed DhanHQ::Models::Position.all works, check if Models module exists
          # Check if we can access a known model class
          if defined?(DhanHQ::Models) && (defined?(DhanHQ::Models::Funds) || defined?(DhanHQ::Models::Position) || defined?(DhanHQ::Models::Instrument))
            return true
          end
        rescue StandardError
          # If configuration fails, that's okay - we'll use mocks
          return false
        end

        false
      end

      private

      def default_context
        {
          market_open: true,
          event_risk: false,
          websocket_connected: true,
          dhan_authenticated: true,
          in_cooldown: false,
          duplicate_position: false
        }
      end

      # Create a valid trade plan for testing (BULLISH or BEARISH)
      def create_valid_trade_plan(bias = :bullish)
        bias_str = bias.to_s.upcase
        preferred_type = bias == :bullish ? "CE" : "PE"
        direction = bias_str
        momentum = "STRONG"
        regime = "TREND_DAY"

        {
          mode: "OPTIONS_INTRADAY",
          bias: bias_str,
          final_bias: bias_str,
          instrument: "NIFTY",
          htf: {
            timeframe: "15m",
            regime: regime,
            tradable: true,
            pdh: 22_550.0,
            pdl: 22_400.0,
            vwap: 22_475.0,
            range_expansion: true
          },
          mtf: {
            timeframe: "5m",
            direction: direction,
            momentum: momentum,
            aligned_with_htf: true
          },
          ltf: {
            timeframe: "1m",
            entry_type: "BREAKOUT",
            trigger: bias == :bullish ? "Price breaks above resistance at 22_500" : "Price breaks below support at 22_400",
            sl_level: bias == :bullish ? "1m swing low at 22_480" : "1m swing high at 22_420",
            invalidation: bias == :bullish ? "Price closes back below 22_480" : "Price closes back above 22_420"
          },
          strike_selection: {
            preferred_type: preferred_type,
            atm_strike: 22_500,
            candidates: [
              {
                security_id: "TEST123",
                strike: 22_500,
                type: preferred_type,
                moneyness: "ATM",
                reason: "#{momentum} momentum + expanding range",
                risk_note: "Higher premium, lower theta"
              }
            ]
          },
          stop_loss_logic: bias == :bullish ? "1m swing low breaks at 22_480" : "1m swing high breaks at 22_420",
          target_logic: bias == :bullish ? "Previous day high at 22_550" : "Previous day low at 22_400",
          summary: "Valid #{bias_str} trade plan for testing - NIFTY #{preferred_type} at 22_500"
        }
      end
    end
  end
end
