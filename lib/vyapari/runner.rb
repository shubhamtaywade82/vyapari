# frozen_string_literal: true

module Vyapari
  # Mode router that deterministically routes queries to the appropriate trading mode
  class Runner
    def self.run(query)
      mode = detect_mode(query)

      case mode
      when :options
        # Use new PhasedAgent system
        run_phased_options_agent(query)
      when :swing
        Swing::Agent.new.run(query)
      else
        raise Error, "Unsupported trading mode detected"
      end
    end

    def self.detect_mode(query)
      # Deterministic rule-based detection (no LLM guessing)
      return :options if query.match?(/option|ce|pe|expiry|intraday/i)
      :swing
    end

    # Run options trading using the new PhasedAgent system
    def self.run_phased_options_agent(query)
      require_relative "options/complete_integration"

      # Use CompleteIntegration to set up and run the phased agent
      result = Options::CompleteIntegration.run_complete_workflow(
        task: query,
        dry_run: ENV.fetch("DRY_RUN", "true") == "true"
      )

      # Format result for CLI output
      format_result(result[:result])
    end

    # Format the result for CLI display
    def self.format_result(result)
      return "No result" unless result

      output = []
      output << "\n" + "=" * 70
      output << "TRADING ANALYSIS RESULT"
      output << "=" * 70

      if result[:final_status]
        output << "\nStatus: #{result[:final_status].upcase}"
        output << "Output: #{result[:final_output]}" if result[:final_output]
      end

      if result[:phases]
        output << "\nPhase Results:"
        result[:phases].each do |phase, phase_result|
          next unless phase_result.is_a?(Hash)
          output << "\n  #{phase.to_s.upcase}:"
          output << "    Status: #{phase_result[:status]}" if phase_result[:status]
          output << "    Iterations: #{phase_result[:iterations]}/#{phase_result[:max_iterations]}" if phase_result[:iterations]
        end
      end

      if result[:order_id]
        output << "\nOrder ID: #{result[:order_id]}"
      end

      output << "\n" + "=" * 70
      output.join("\n")
    end
  end
end
