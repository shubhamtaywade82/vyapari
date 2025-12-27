#!/usr/bin/env ruby
# frozen_string_literal: true

# Test all phases script - forces progression through all modules

require "bundler/setup"
require_relative "../lib/vyapari"

# Enable test mode
ENV["VYAPARI_TEST_MODE"] = "true"
ENV["DRY_RUN"] = "true"
ENV["DEBUG"] = "true"

query = ARGV[0] || "Analyze NIFTY for options buying"

puts "\n" + "=" * 80
puts "VYAPARI - TEST ALL PHASES MODE"
puts "=" * 80
puts "This mode will test ALL phases even if market analysis says NO_TRADE"
puts "=" * 80
puts ""

begin
  result = Vyapari::Options::CompleteIntegration.run_complete_workflow(
    task: query,
    dry_run: true
  )

  workflow_result = result[:result]

  puts "\n" + "=" * 80
  puts "PHASE TESTING RESULTS"
  puts "=" * 80
  puts ""

  # Check each phase
  phases_tested = []

  if workflow_result[:phases]
    workflow_result[:phases].each do |phase_name, phase_result|
      next unless phase_result.is_a?(Hash)

      status = phase_result[:status]
      iterations = phase_result[:iterations] || 0

      next unless status

      phases_tested << phase_name
      status_icon = %w[completed approved executed].include?(status) ? "✅" : "⚠️"
      puts "#{status_icon} Phase: #{phase_name.to_s.upcase}"
      puts "   Status: #{status}"
      puts "   Iterations: #{iterations}"
      puts ""
    end
  end

  puts "=" * 80
  puts "SUMMARY"
  puts "=" * 80
  puts "Phases tested: #{phases_tested.length}/3"
  puts "  - Analysis: #{phases_tested.include?(:analysis) ? "✅" : "❌"}"
  puts "  - Validation: #{phases_tested.include?(:validation) ? "✅" : "❌"}"
  puts "  - Execution: #{phases_tested.include?(:execution) ? "✅" : "❌"}"
  puts ""
  puts "Final Status: #{workflow_result[:final_status]}"
  puts "Total LLM Calls: #{result[:total_llm_calls]}"
  puts ""

  if phases_tested.length == 3
    puts "✅ ALL PHASES TESTED SUCCESSFULLY!"
  else
    puts "⚠️  Some phases were not tested"
  end
rescue StandardError => e
  puts "\n❌ ERROR: #{e.class}: #{e.message}"
  puts "\nBacktrace:"
  puts e.backtrace.first(10).join("\n")
  exit 1
end
