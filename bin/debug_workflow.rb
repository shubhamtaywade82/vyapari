#!/usr/bin/env ruby
# frozen_string_literal: true

# Debug workflow script - shows detailed execution trace

require "bundler/setup"
require_relative "../lib/vyapari"

# Enable maximum debugging
ENV["DEBUG"] = "true"
ENV["VYAPARI_LOG_LEVEL"] = "DEBUG"

query = ARGV[0] || "Analyze NIFTY for options buying"

puts "\n" + "=" * 80
puts "VYAPARI WORKFLOW DEBUG MODE"
puts "=" * 80
puts "Query: #{query}"
puts "=" * 80
puts ""

# Monkey patch to add detailed logging
module Vyapari
  module Options
    class PhasedAgent
      alias_method :original_run, :run

      def run(task, context: {})
        puts "\n🔍 [DEBUG] Starting PhasedAgent.run"
        puts "   Task: #{task}"
        puts "   Context keys: #{context.keys.join(', ')}"

        result = original_run(task, context: context)

        puts "\n🔍 [DEBUG] PhasedAgent.run completed"
        puts "   Final status: #{result[:final_status]}"
        puts "   Phases: #{result[:phases].keys.join(', ')}"

        result
      end
    end
  end
end

# Run with detailed output
begin
  result = Vyapari::Options::CompleteIntegration.run_complete_workflow(
    task: query,
    dry_run: true
  )

  puts "\n" + "=" * 80
  puts "DETAILED RESULTS"
  puts "=" * 80

  # Pretty print the result
  require "json"
  puts JSON.pretty_generate(result[:result])

rescue StandardError => e
  puts "\n❌ ERROR: #{e.class}: #{e.message}"
  puts "\nBacktrace:"
  puts e.backtrace.first(15).join("\n")
end

