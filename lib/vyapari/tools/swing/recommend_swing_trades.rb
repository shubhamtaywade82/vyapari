# frozen_string_literal: true

require "json"

module Vyapari
  module Tools
    module Swing
      # Tool for LLM to provide swing trading recommendations (entry, SL, TP, HOLD)
      class RecommendSwingTrades < Base
        def self.name = "recommend_swing_trades"

        def self.schema
          {
            type: "function",
            function: {
              name: name,
              description: "Provides swing trading recommendations (entry price, stop loss, targets, holding period) for ALL analyzed candidates. This is the final step - LLM synthesizes the technical analysis and provides actionable recommendations for EACH candidate. The candidates parameter is automatically injected from batch_analyze_universe result.",
              parameters: {
                type: "object",
                properties: {
                  candidates: {
                    type: "array",
                    description: "Array of top analyzed candidates with scores and technicals. Automatically injected from batch_analyze_universe result.",
                    items: { type: "object" }
                  }
                },
                required: ["candidates"]
              }
            }
          }
        end

        def call(params)
          candidates = params["candidates"] || params[:candidates] || []

          raise "Candidates must be an array" unless candidates.is_a?(Array)
          raise "Candidates array is empty" if candidates.empty?

          # This tool validates candidates and returns them
          # The LLM will provide recommendations in its response for ALL candidates
          {
            "candidates_received" => candidates.size,
            "message" => "Candidates ready for LLM recommendation. LLM MUST provide entry, SL, TP, and holding period for ALL #{candidates.size} candidates, not just one.",
            "candidates_count" => candidates.size,
            "sample_candidate" => candidates.first # Show structure
          }
        rescue StandardError => e
          {
            "error" => e.message,
            "candidates_received" => 0
          }
        end
      end
    end
  end
end

