# frozen_string_literal: true

# require_relative "../../indicators/ema"
require_relative "base"

module Vyapari
  module Tools
    # Tool for analyzing 15-minute market structure
    # Detects HH/HL (bullish) or LL/LH (bearish) using swing highs/lows
    # Returns: bullish, bearish, or range
    # If result is 'range', options buying must be avoided
    class AnalyzeStructure15m < Base
      def self.name = "analyze_structure_15m"

      def self.schema
        {
          type: "function",
          function: {
            name: name,
            description: <<~DESC,
              STEP 2A: Analyzes 15-minute market structure.
              Detects HH/HL or LL/LH using swing highs/lows.
              Returns: bullish, bearish, or range.
              If result is 'range', options buying must be avoided.
              Candles are auto-injected from context.
            DESC
            parameters: {
              type: "object",
              properties: {},
              required: []
            }
          }
        }
      end

      def call(p)
        candles = p["candles"] || p[:candles]
        raise ArgumentError, "candles must be an array" unless candles.is_a?(Array)
        return range("Not enough candles") if candles.size < 40

        swings = detect_swings(candles)

        return range("Insufficient swing points") if swings[:highs].size < 2 || swings[:lows].size < 2

        last_highs = swings[:highs].last(2)
        last_lows  = swings[:lows].last(2)

        closes = candles.map { |c| (c["close"] || c[:close]).to_f }
        ema20 = Indicators::EMA.calculate(closes, 20)

        last_close = (candles.last["close"] || candles.last[:close]).to_f

        # Bullish structure: HH + HL + price above EMA
        if higher_high?(last_highs) &&
           higher_low?(last_lows) &&
           last_close > ema20
          bullish(swings, ema20, last_close)

        # Bearish structure: LL + LH + price below EMA
        elsif lower_low?(last_lows) &&
              lower_high?(last_highs) &&
              last_close < ema20
          bearish(swings, ema20, last_close)

        else
          range("Structure not aligned")
        end
      end

      private

      # ---- STRUCTURE HELPERS ----

      def detect_swings(candles)
        highs = []
        lows  = []

        (1...(candles.size - 1)).each do |i|
          prev = candles[i - 1]
          curr = candles[i]
          nxt  = candles[i + 1]

          prev_high = (prev["high"] || prev[:high]).to_f
          curr_high = (curr["high"] || curr[:high]).to_f
          nxt_high  = (nxt["high"] || nxt[:high]).to_f

          if curr_high > prev_high && curr_high > nxt_high
            highs << { index: i, price: curr_high }
          end

          prev_low = (prev["low"] || prev[:low]).to_f
          curr_low = (curr["low"] || curr[:low]).to_f
          nxt_low  = (nxt["low"] || nxt[:low]).to_f

          if curr_low < prev_low && curr_low < nxt_low
            lows << { index: i, price: curr_low }
          end
        end

        { highs: highs, lows: lows }
      end

      def higher_high?(highs)
        return false if highs.size < 2
        highs.last[:price] > highs.first[:price]
      end

      def higher_low?(lows)
        return false if lows.size < 2
        lows.last[:price] > lows.first[:price]
      end

      def lower_low?(lows)
        return false if lows.size < 2
        lows.last[:price] < lows.first[:price]
      end

      def lower_high?(highs)
        return false if highs.size < 2
        highs.last[:price] < highs.first[:price]
      end

      # ---- OUTPUT BUILDERS ----

      def bullish(swings, ema, close)
        {
          "structure" => "bullish",
          "valid" => true,
          "ema20" => ema.round(2),
          "last_close" => close.round(2),
          "reason" => "15m HH/HL with price above EMA20"
        }
      end

      def bearish(swings, ema, close)
        {
          "structure" => "bearish",
          "valid" => true,
          "ema20" => ema.round(2),
          "last_close" => close.round(2),
          "reason" => "15m LL/LH with price below EMA20"
        }
      end

      def range(reason)
        {
          "structure" => "range",
          "valid" => false,
          "reason" => reason
        }
      end
    end
  end
end

