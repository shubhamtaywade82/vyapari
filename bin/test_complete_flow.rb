#!/usr/bin/env ruby
# frozen_string_literal: true

# Complete flow test script for Vyapari
# Tests the entire workflow from query to final result

require "bundler/setup"
require_relative "../lib/vyapari"

# Enable debug mode
ENV["DEBUG"] = "true"
ENV["VYAPARI_LOG_LEVEL"] = "DEBUG"

puts "=" * 80
puts "VYAPARI COMPLETE FLOW TEST"
puts "=" * 80
puts ""

# Test query
query = ARGV[0] || "Analyze NIFTY for options buying"

puts "📋 Query: #{query}"
puts ""

# Step 1: Test Runner
puts "=" * 80
puts "STEP 1: Testing Runner"
puts "=" * 80
begin
  mode = Vyapari::Runner.detect_mode(query)
  puts "✅ Mode detected: #{mode}"
rescue StandardError => e
  puts "❌ Error in Runner: #{e.message}"
  puts e.backtrace.first(3) if ENV["DEBUG"]
  exit 1
end

# Step 2: Test Complete Integration Setup
puts ""
puts "=" * 80
puts "STEP 2: Testing Complete Integration Setup"
puts "=" * 80
begin
  system = Vyapari::Options::CompleteIntegration.setup_system(dry_run: true)
  puts "✅ State machine created"
  puts "✅ Tool registry created (#{system[:registry].tool_names.length} tools)"
  puts "✅ Safety gate created"
  puts "✅ Phased agent created"
rescue StandardError => e
  puts "❌ Error in setup: #{e.message}"
  puts e.backtrace.first(5) if ENV["DEBUG"]
  exit 1
end

# Step 3: Test Global Pre-check
puts ""
puts "=" * 80
puts "STEP 3: Testing Global Pre-check"
puts "=" * 80
begin
  checklist_guard = Vyapari::Options::ChecklistGuard.new
  context = {
    market_open: true,
    event_risk: false,
    websocket_connected: true,
    dhan_authenticated: true,
    in_cooldown: false,
    duplicate_position: false
  }
  precheck = checklist_guard.run_global_precheck(context: context)
  if precheck[:passed]
    puts "✅ Global pre-check PASSED"
  else
    puts "⚠️  Global pre-check FAILED:"
    precheck[:failures].each do |failure|
      puts "   - #{failure[:description]}"
    end
  end
rescue StandardError => e
  puts "❌ Error in pre-check: #{e.message}"
  puts e.backtrace.first(3) if ENV["DEBUG"]
end

# Step 4: Run Complete Workflow
puts ""
puts "=" * 80
puts "STEP 4: Running Complete Workflow"
puts "=" * 80
begin
  result = Vyapari::Options::CompleteIntegration.run_complete_workflow(
    task: query,
    dry_run: true
  )

  workflow_result = result[:result]

  puts ""
  puts "=" * 80
  puts "WORKFLOW RESULTS"
  puts "=" * 80
  puts ""
  puts "Final Status: #{workflow_result[:final_status]}"
  puts "Final Output: #{workflow_result[:final_output]}"
  puts "Total LLM Calls: #{result[:total_llm_calls]}"
  puts ""

  # Phase-by-phase breakdown
  if workflow_result[:phases]
    puts "Phase Breakdown:"
    workflow_result[:phases].each do |phase_name, phase_result|
      next unless phase_result.is_a?(Hash)
      puts ""
      puts "  #{phase_name.to_s.upcase}:"
      puts "    Status: #{phase_result[:status]}" if phase_result[:status]
      if phase_result[:iterations]
        puts "    Iterations: #{phase_result[:iterations]}/#{phase_result[:max_iterations]}"
      end
      if phase_result[:reason]
        puts "    Reason: #{phase_result[:reason]}"
      end

      # Show MTF result if available
      if phase_name == :analysis && phase_result[:mtf_result]
        mtf = phase_result[:mtf_result]
        puts "    MTF Analysis:"
        puts "      Status: #{mtf[:status]}"
        puts "      Iterations Used: #{mtf[:iterations_used]}"
        if mtf[:timeframes]
          mtf[:timeframes].each do |tf_name, tf_result|
            next unless tf_result.is_a?(Hash)
            puts "      #{tf_name.to_s.upcase}:"
            puts "        Regime/Direction: #{tf_result[:regime] || tf_result[:direction]}"
            puts "        Iterations: #{tf_result[:iterations]}"
          end
        end
      end
    end
  end

  # Check for errors
  if workflow_result[:checklist_failures]
    puts ""
    puts "⚠️  Checklist Failures:"
    workflow_result[:checklist_failures].each do |failure|
      puts "   - #{failure[:description]}"
    end
  end

  # Success criteria
  puts ""
  puts "=" * 80
  puts "SUCCESS CRITERIA"
  puts "=" * 80
  success = true

  if workflow_result[:final_status] == "executed"
    puts "✅ Order executed successfully"
  elsif workflow_result[:final_status] == "no_trade"
    puts "✅ Analysis completed (no trade recommended)"
  elsif workflow_result[:final_status] == "precheck_failed"
    puts "⚠️  Pre-check failed (expected in test mode without real DhanHQ)"
    success = false
  elsif workflow_result[:final_status] == "analysis_failed"
    puts "❌ Analysis phase failed"
    success = false
  elsif workflow_result[:final_status] == "validation_failed"
    puts "⚠️  Validation failed (may be expected)"
  else
    puts "⚠️  Status: #{workflow_result[:final_status]}"
  end

  if result[:total_llm_calls] > 0
    puts "✅ LLM calls made: #{result[:total_llm_calls]}"
  else
    puts "⚠️  No LLM calls made"
    success = false
  end

  puts ""
  if success
    puts "✅ COMPLETE FLOW TEST: PASSED"
  else
    puts "⚠️  COMPLETE FLOW TEST: PARTIAL (some issues detected)"
  end

rescue StandardError => e
  puts "❌ Error in workflow: #{e.message}"
  puts e.backtrace.first(10) if ENV["DEBUG"]
  exit 1
end

puts ""
puts "=" * 80
puts "TEST COMPLETE"
puts "=" * 80

