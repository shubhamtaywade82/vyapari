# frozen_string_literal: true

require "json"

module Vyapari
  module Tools
    # Tool for analyzing market trends
    class AnalyzeTrend < Base
      def self.name = "analyze_trend"

      def self.schema
        {
          type: "function",
          function: {
            name: name,
            description: "STEP 3: Analyzes market trends based on candle data from fetch_intraday_history. MUST be called after fetch_intraday_history. Uses RSI, ADX, and EMA indicators. Returns trend: 'bullish', 'bearish', or 'avoid'. If 'avoid', do NOT call fetch_option_chain.",
            parameters: {
              type: "object",
              properties: {
                candles: { type: "array" }
              },
              required: ["candles"]
            }
          }
        }
      end

      def call(p)
        # Handle case where LLM passes candles as a JSON string instead of array
        candles_data = p["candles"]
        candles_data = JSON.parse(candles_data) if candles_data.is_a?(String)
        candles_data = [] if candles_data.nil?

        raise ArgumentError, "candles must be an array" unless candles_data.is_a?(Array)

        # If candles array is empty, return avoid trend with explanation
        if candles_data.empty?
          return {
            trend: "avoid",
            rsi: 0,
            adx: 0,
            ema_fast: 0,
            ema_slow: 0,
            recommendation: "No historical data available - cannot analyze trend. Market may be closed or data unavailable."
          }
        end

        closes = candles_data.map { |c| c["close"] || c[:close] }.map(&:to_f)

        # Calculate indicators
        rsi = Indicators::RSI.calculate(closes) # Range: 0-100 (momentum)
        adx = Indicators::ADX.calculate(candles_data) # Range: 0-100 (trend strength)
        ema_fast = Indicators::EMA.calculate(closes, 9) # Short-term trend (9 periods)
        ema_slow = Indicators::EMA.calculate(closes, 21) # Long-term trend (21 periods)

        # Trend determination logic:
        # - ADX > 25: Strong trend exists
        # - ADX ≤ 25: Weak/choppy market → AVOID
        # - EMA Fast > Slow: Uptrend (bullish)
        # - EMA Fast < Slow: Downtrend (bearish)
        trend =
          if adx > 25 && ema_fast > ema_slow
            "bullish"
          elsif adx > 25 && ema_fast < ema_slow
            "bearish"
          else
            "avoid" # ADX ≤ 25 or unclear EMA relationship = choppy market
          end

        pp trend
        pp rsi
        pp adx
        pp ema_fast
        pp ema_slow
        pp trend == "avoid" ? "Avoid trading - market is choppy" : "Market trend is #{trend.upcase}"
        {
          trend: trend,
          rsi: rsi,
          adx: adx,
          ema_fast: ema_fast,
          ema_slow: ema_slow,
          recommendation: trend == "avoid" ? "Avoid trading - market is choppy" : "Market trend is #{trend.upcase}"
        }
      end
    end
  end
end
