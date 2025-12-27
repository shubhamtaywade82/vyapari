# frozen_string_literal: true

require "json"
require "set"

module Vyapari
  module Tools
    module Swing
      # Tool for filtering the swing trading universe to a manageable size
      class FilterUniverse < Base
        def self.name = "filter_universe"

        def self.schema
          {
            type: "function",
            function: {
              name: name,
              description: "Filters the swing trading universe to a smaller, manageable list for analysis. Use this after fetch_universe to reduce the candidate list.",
              parameters: {
                type: "object",
                properties: {
                  universe: {
                    type: "array",
                    description: "Array of stock symbols to filter (from fetch_universe result). If not provided, will use empty array.",
                    items: { type: "string" }
                  },
                  limit: {
                    type: "integer",
                    description: "Maximum number of stocks to return. Default: 50. Recommended: 20-100 for swing trading analysis.",
                    minimum: 1,
                    maximum: 500
                  },
                  strategy: {
                    type: "string",
                    description: "Filtering strategy: 'top_large_cap' (prioritize Nifty50), 'random' (random sample), 'first' (first N symbols). Default: 'top_large_cap'",
                    enum: ["top_large_cap", "random", "first"]
                  },
                  exclude_symbols: {
                    type: "array",
                    description: "Optional: Array of symbols to exclude from the filtered list",
                    items: { type: "string" }
                  }
                },
                required: []
              }
            }
          }
        end

        def call(params)
          universe_raw = params["universe"] || params[:universe] || []

          # Handle string representation of array (LLM sometimes passes as string)
          universe = if universe_raw.is_a?(String)
            # Try to parse as JSON array
            begin
              JSON.parse(universe_raw)
            rescue JSON::ParserError
              # Try to extract array from string like "['SYMBOL1','SYMBOL2']" or '["SYMBOL1","SYMBOL2"]'
              # Remove brackets and quotes, split by comma
              cleaned = universe_raw.strip
              cleaned = cleaned.gsub(/^\[/, "").gsub(/\]$/, "")
              cleaned.split(",").map do |item|
                item.strip.gsub(/^['"]/, "").gsub(/['"]$/, "")
              end.reject(&:empty?)
            end
          else
            universe_raw
          end

          limit = (params["limit"] || params[:limit] || 50).to_i
          strategy = (params["strategy"] || params[:strategy] || "top_large_cap").to_s
          exclude_symbols = (params["exclude_symbols"] || params[:exclude_symbols] || []).map(&:upcase).to_set

          # Validate inputs
          raise "Universe must be an array, got #{universe.class}" unless universe.is_a?(Array)
          raise "Limit must be between 1 and 500" unless limit.between?(1, 500)

          # Filter out excluded symbols
          filtered = universe.reject { |sym| exclude_symbols.include?(sym.to_s.upcase) }

          # Apply filtering strategy
          result = case strategy
          when "top_large_cap"
            filter_top_large_cap(filtered, limit)
          when "random"
            filter_random(filtered, limit)
          when "first"
            filter_first(filtered, limit)
          else
            filter_top_large_cap(filtered, limit)
          end

          {
            "filtered_universe" => result,
            "original_count" => universe.size,
            "filtered_count" => result.size,
            "strategy" => strategy,
            "limit" => limit
          }
        rescue StandardError => e
          {
            "error" => e.message,
            "filtered_universe" => [],
            "original_count" => 0,
            "filtered_count" => 0
          }
        end

        private

        # Prioritize large cap stocks (common in Nifty50)
        # This is a heuristic - assumes symbols appearing first in sorted lists
        # are more likely to be large cap
        def filter_top_large_cap(universe, limit)
          # Common large cap stocks (Nifty50 constituents typically)
          # These are usually the first symbols alphabetically in most indices
          large_cap_indicators = %w[
            RELIANCE HDFCBANK TCS INFY ICICIBANK HDFC BHARTIARTL SBIN BAJFINANCE
            KOTAKBANK LT ITC AXISBANK ASIANPAINT MARUTI TITAN NESTLEIND ULTRACEMCO
            WIPRO POWERGRID ONGC NTPC HINDALCO JSWSTEEL TATASTEEL ADANIENT ADANIPORTS
            BAJAJFINSV HCLTECH SUNPHARMA TECHM CIPLA DRREDDY HEROMOTOCO INDUSINDBK
            COALINDIA IOC BPCL GAIL M&M EICHERMOT DIVISLAB GRASIM TATACONSUM
            BRITANNIA APOLLOHOSP DABUR GODREJCP PIDILITIND SHREECEM TATAMOTORS
          ].map(&:upcase).to_set

          # Split into large cap and others
          large_caps = []
          others = []

          universe.each do |symbol|
            sym_up = symbol.to_s.upcase
            if large_cap_indicators.include?(sym_up)
              large_caps << symbol
            else
              others << symbol
            end
          end

          # Prioritize large caps, then fill with others
          result = large_caps.first(limit)
          remaining = limit - result.size
          result.concat(others.first(remaining)) if remaining > 0

          result.first(limit)
        end

        def filter_random(universe, limit)
          universe.shuffle.first(limit)
        end

        def filter_first(universe, limit)
          universe.first(limit)
        end
      end
    end
  end
end

