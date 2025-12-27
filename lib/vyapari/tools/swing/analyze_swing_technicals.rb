# frozen_string_literal: true

require "json"

# Indicators are loaded globally via lib/vyapari.rb
# Path from lib/vyapari/tools/swing/ to lib/indicators/
require_relative "../../../indicators/rsi"
require_relative "../../../indicators/ema"
require_relative "../../../indicators/adx"
require_relative "../base"

module Vyapari
  module Tools
    module Swing
      # Tool for analyzing swing trading technical indicators
      class AnalyzeSwingTechnicals < Base
        def self.name = "analyze_swing_technicals"

        def self.schema
          {
            type: "function",
            function: {
              name: name,
              description: "Analyzes swing trading technical indicators (EMA, RSI, ADX, structure, ATR) from historical data. Returns trend, momentum, and structure analysis.",
              parameters: {
                type: "object",
                properties: {
                  symbol: {
                    type: "string",
                    description: "Stock symbol being analyzed"
                  },
                  candles_1h: {
                    type: "array",
                    description: "1H hourly candles array from fetch_swing_history"
                  },
                  candles_1d: {
                    type: "array",
                    description: "1D daily candles array from fetch_swing_history"
                  }
                },
                required: ["symbol", "candles_1d"]
              }
            }
          }
        end

        def call(params)
          symbol = params["symbol"] || params[:symbol]
          candles_1h_raw = params["candles_1h"] || params[:candles_1h] || []
          candles_1d_raw = params["candles_1d"] || params[:candles_1d] || []

          raise "Symbol parameter is required" if symbol.nil? || symbol.to_s.strip.empty?

          # Handle string inputs (LLM sometimes passes as JSON string)
          candles_1h = normalize_candles(candles_1h_raw)
          candles_1d = normalize_candles(candles_1d_raw)

          raise "Daily candles (candles_1d) are required" if candles_1d.empty?

          # Analyze using daily timeframe (primary for swing trading)
          daily_analysis = analyze_timeframe(candles_1d, "1d")

          # Analyze hourly if available (secondary confirmation)
          hourly_analysis = candles_1h.any? ? analyze_timeframe(candles_1h, "1h") : nil

          # Determine overall trend
          trend = determine_trend(daily_analysis, hourly_analysis)

          # Calculate ATR for stop loss sizing
          atr = calculate_atr(candles_1d, period: 14)

          {
            "symbol" => symbol.to_s.upcase,
            "timeframe" => "1D",
            "trend" => trend,
            "trend_strength" => daily_analysis[:trend_strength],
            "rsi" => daily_analysis[:rsi],
            "ema_alignment" => daily_analysis[:ema_alignment],
            "structure" => daily_analysis[:structure],
            "adx" => daily_analysis[:adx],
            "atr" => atr,
            "current_price" => daily_analysis[:current_price],
            "hourly_confirmation" => hourly_analysis ? {
              "trend" => hourly_analysis[:trend],
              "rsi" => hourly_analysis[:rsi]
            } : nil
          }
        rescue StandardError => e
          {
            "error" => e.message,
            "symbol" => symbol.to_s.upcase,
            "trend" => "unknown"
          }
        end

        private

        def normalize_candles(candles_input)
          return [] if candles_input.nil?

          # If already an array, return as-is
          return candles_input if candles_input.is_a?(Array)

          # If string, try to parse as JSON
          if candles_input.is_a?(String)
            begin
              parsed = JSON.parse(candles_input)
              return parsed if parsed.is_a?(Array)
            rescue JSON::ParserError
              # Not JSON, return empty
            end
          end

          # If hash, try to extract array
          if candles_input.is_a?(Hash)
            return candles_input.values if candles_input.values.first.is_a?(Hash)
          end

          []
        end

        def analyze_timeframe(candles, timeframe)
          return default_analysis if candles.empty?

          # Extract closing prices
          closes = candles.map { |c| (c["close"] || c[:close] || 0).to_f }.compact
          return default_analysis if closes.empty?

          current_price = closes.last

          # Calculate indicators
          rsi = Indicators::RSI.calculate(closes, period: 14)
          ema_20 = Indicators::EMA.calculate(closes, period: 20)
          ema_50 = Indicators::EMA.calculate(closes, period: 50)
          adx = Indicators::ADX.calculate(candles, period: 14)

          # Determine EMA alignment
          ema_alignment = if ema_20 > ema_50
            "20>50" # Bullish alignment
          elsif ema_20 < ema_50
            "20<50" # Bearish alignment
          else
            "neutral"
          end

          # Determine structure (Higher Highs / Lower Lows)
          structure = analyze_structure(closes)

          # Determine trend strength
          trend_strength = if adx > 25
            "strong"
          elsif adx > 20
            "moderate"
          else
            "weak"
          end

          # Determine trend direction
          trend = if ema_alignment == "20>50" && rsi > 50 && structure.start_with?("HH")
            "bullish"
          elsif ema_alignment == "20<50" && rsi < 50 && structure.start_with?("LL")
            "bearish"
          else
            "neutral"
          end

          {
            trend: trend,
            trend_strength: trend_strength,
            rsi: rsi.round(2),
            ema_20: ema_20.round(2),
            ema_50: ema_50.round(2),
            ema_alignment: ema_alignment,
            structure: structure,
            adx: adx.round(2),
            current_price: current_price.round(2)
          }
        end

        def analyze_structure(prices)
          return "neutral" if prices.length < 4

          # Look for Higher Highs (HH) and Higher Lows (HL) for bullish
          # Look for Lower Highs (LH) and Lower Lows (LL) for bearish
          recent_prices = prices.last(20) # Last 20 periods

          highs = []
          lows = []

          # Simple peak/trough detection
          (1...recent_prices.length - 1).each do |i|
            if recent_prices[i] > recent_prices[i - 1] && recent_prices[i] > recent_prices[i + 1]
              highs << { index: i, price: recent_prices[i] }
            elsif recent_prices[i] < recent_prices[i - 1] && recent_prices[i] < recent_prices[i + 1]
              lows << { index: i, price: recent_prices[i] }
            end
          end

          return "neutral" if highs.length < 2 || lows.length < 2

          # Check for Higher Highs
          last_two_highs = highs.last(2)
          higher_highs = last_two_highs.length == 2 && last_two_highs[1][:price] > last_two_highs[0][:price]

          # Check for Higher Lows
          last_two_lows = lows.last(2)
          higher_lows = last_two_lows.length == 2 && last_two_lows[1][:price] > last_two_lows[0][:price]

          # Check for Lower Highs
          lower_highs = last_two_highs.length == 2 && last_two_highs[1][:price] < last_two_highs[0][:price]

          # Check for Lower Lows
          lower_lows = last_two_lows.length == 2 && last_two_lows[1][:price] < last_two_lows[0][:price]

          if higher_highs && higher_lows
            "HH_HL" # Bullish structure
          elsif lower_highs && lower_lows
            "LL_LH" # Bearish structure
          elsif higher_highs
            "HH" # Higher highs but not higher lows
          elsif lower_lows
            "LL" # Lower lows but not lower highs
          else
            "neutral"
          end
        end

        def calculate_atr(candles, period: 14)
          return 0.0 if candles.length < period + 1

          true_ranges = []

          (1...candles.length).each do |i|
            high = (candles[i]["high"] || candles[i][:high] || 0).to_f
            low = (candles[i]["low"] || candles[i][:low] || 0).to_f
            prev_close = (candles[i - 1]["close"] || candles[i - 1][:close] || 0).to_f

            tr1 = high - low
            tr2 = (high - prev_close).abs
            tr3 = (low - prev_close).abs

            true_ranges << [tr1, tr2, tr3].max
          end

          return 0.0 if true_ranges.empty?

          # Calculate ATR as average of true ranges
          atr = true_ranges.last(period).sum.to_f / period
          atr.round(2)
        end

        def determine_trend(daily_analysis, hourly_analysis)
          daily_trend = daily_analysis[:trend]

          # Use hourly as confirmation if available
          if hourly_analysis
            hourly_trend = hourly_analysis[:trend]
            # If both agree, use daily. If they conflict, use daily (higher timeframe wins)
            return daily_trend
          end

          daily_trend
        end

        def default_analysis
          {
            trend: "unknown",
            trend_strength: "unknown",
            rsi: 50.0,
            ema_20: 0.0,
            ema_50: 0.0,
            ema_alignment: "neutral",
            structure: "neutral",
            adx: 0.0,
            current_price: 0.0
          }
        end
      end
    end
  end
end

