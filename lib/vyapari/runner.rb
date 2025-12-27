# frozen_string_literal: true

module Vyapari
  # Mode router that deterministically routes queries to the appropriate trading mode
  class Runner
    def self.run(query)
      mode = detect_mode(query)

      case mode
      when :options
        Options::Agent.new.run(query)
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
  end
end

