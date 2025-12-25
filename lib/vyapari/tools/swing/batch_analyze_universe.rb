# frozen_string_literal: true

require "json"
require_relative "fetch_swing_history"
require_relative "analyze_swing_technicals"

module Vyapari
  module Tools
    module Swing
      # Tool that batch analyzes all stocks in the universe (Ruby does the work, not LLM)
      class BatchAnalyzeUniverse < Base
        def self.name = "batch_analyze_universe"

        def self.schema
          {
            type: "function",
            function: {
              name: name,
              description: "Batch analyzes all stocks in the filtered universe. This tool processes all stocks in Ruby (efficient), fetches history, calculates technicals, and scores each stock. Returns ranked candidates ready for LLM recommendation. The universe parameter is automatically injected from context.",
              parameters: {
                type: "object",
                properties: {
                  limit: {
                    type: "integer",
                    description: "Maximum number of top candidates to return after analysis. Default: 20.",
                    minimum: 5,
                    maximum: 50
                  }
                },
                required: []
              }
            }
          }
        end

        def call(params)
          universe = params["universe"] || params[:universe] || []
          limit = (params["limit"] || params[:limit] || 20).to_i

          raise "Universe must be an array" unless universe.is_a?(Array)
          raise "Universe is empty" if universe.empty?

          # Limit processing to avoid timeouts (process max 10 stocks initially for testing)
          max_stocks = [universe.size, 10].min
          stocks_to_process = universe.first(max_stocks)

          warn "📊 Batch analyzing #{stocks_to_process.size} stocks (limited from #{universe.size} to avoid timeout)..." if defined?(warn)

          # Initialize tools
          history_tool = FetchSwingHistory.new
          analysis_tool = AnalyzeSwingTechnicals.new

          # Analyze each stock (Ruby does the work, not LLM)
          analyzed_stocks = []
          errors = []
          start_time = Time.now

          stocks_to_process.each_with_index do |symbol, index|
            symbol_str = symbol.to_s.upcase.strip
            next if symbol_str.empty?

            begin
              stock_start = Time.now
              warn "       🔄 [#{index + 1}/#{stocks_to_process.size}] Processing #{symbol_str}..." if defined?(warn) && index < 3

              # Fetch history
              history_result = history_tool.call({ "symbol" => symbol_str })

              if history_result["error"] || history_result["1d"].nil? || history_result["1d"].empty?
                errors << { "symbol" => symbol_str, "error" => "No daily data" }
                next
              end

              # Analyze technicals
              analysis_result = analysis_tool.call({
                "symbol" => symbol_str,
                "candles_1h" => history_result["1h"] || [],
                "candles_1d" => history_result["1d"] || []
              })

              next if analysis_result["error"] || analysis_result["trend"] == "unknown"

              # Score the stock
              score = calculate_score(analysis_result)

              analyzed_stocks << {
                "symbol" => symbol_str,
                "score" => score,
                "max_score" => 10,
                "trend" => analysis_result["trend"],
                "trend_strength" => analysis_result["trend_strength"],
                "rsi" => analysis_result["rsi"],
                "ema_alignment" => analysis_result["ema_alignment"],
                "structure" => analysis_result["structure"],
                "adx" => analysis_result["adx"],
                "atr" => analysis_result["atr"],
                "current_price" => analysis_result["current_price"],
                "analysis" => analysis_result
              }

              elapsed = Time.now - stock_start
              # Progress logging (every 3 stocks or last stock)
              if index % 3 == 0 || index == stocks_to_process.size - 1
                warn "       ✅ [#{index + 1}/#{stocks_to_process.size}] #{symbol_str}: score=#{score}, trend=#{analysis_result["trend"]} (#{elapsed.round(1)}s)" if defined?(warn)
              end
            rescue StandardError => e
              errors << { "symbol" => symbol_str, "error" => e.message }
              warn "       ⚠️  #{symbol_str}: #{e.message}" if defined?(warn)
            end
          end

          total_time = Time.now - start_time
          warn "📊 Completed: #{analyzed_stocks.size} analyzed, #{errors.size} errors in #{total_time.round(1)}s" if defined?(warn)

          # Rank by score (highest first)
          ranked = analyzed_stocks.sort_by { |s| -s["score"] }

          # Return top candidates
          top_candidates = ranked.first(limit)

          {
            "analyzed_count" => analyzed_stocks.size,
            "total_stocks" => universe.size,
            "processed_stocks" => stocks_to_process.size,
            "errors_count" => errors.size,
            "top_candidates" => top_candidates,
            "all_analyzed" => analyzed_stocks, # Store all for reference
            "errors" => errors.first(10), # Limit error details
            "processing_time_seconds" => total_time.round(2)
          }
        rescue StandardError => e
          {
            "error" => e.message,
            "analyzed_count" => 0,
            "top_candidates" => []
          }
        end

        private

        def calculate_score(analysis)
          score = 0

          # EMA alignment (bullish = +2, bearish = -1, neutral = 0)
          case analysis["ema_alignment"]
          when "20>50"
            score += 2
          when "20<50"
            score -= 1
          end

          # RSI momentum (50-70 = good, >70 = overbought, <30 = oversold)
          rsi = analysis["rsi"].to_f
          if rsi > 55 && rsi < 70
            score += 2
          elsif rsi > 50 && rsi < 75
            score += 1
          elsif rsi < 30
            score += 1 # Oversold bounce potential
          elsif rsi > 80
            score -= 2 # Overbought
          end

          # ADX trend strength (>25 = strong trend)
          adx = analysis["adx"].to_f
          if adx > 25
            score += 2
          elsif adx > 20
            score += 1
          end

          # Structure (HH_HL = bullish, LL_LH = bearish)
          case analysis["structure"]
          when "HH_HL"
            score += 2
          when "HH"
            score += 1
          when "LL_LH"
            score -= 1
          when "LL"
            score -= 1
          end

          # Trend direction
          case analysis["trend"]
          when "bullish"
            score += 1
          when "bearish"
            score -= 1
          end

          # Trend strength
          case analysis["trend_strength"]
          when "strong"
            score += 1
          when "moderate"
            score += 0.5
          end

          # Ensure score is between 0 and 10
          [[score, 0].max, 10].min.round(1)
        end
      end
    end
  end
end

