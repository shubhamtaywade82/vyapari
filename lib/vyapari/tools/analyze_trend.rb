# frozen_string_literal: true

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
            description: "Analyzes market trends based on candle data",
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
        closes = p["candles"].map { |c| c["close"].to_f }

        rsi = Indicators::RSI.calculate(closes)
        adx = Indicators::ADX.calculate(p["candles"])
        ema_fast = Indicators::EMA.calculate(closes, 9)
        ema_slow = Indicators::EMA.calculate(closes, 21)

        trend =
          if adx > 25 && ema_fast > ema_slow
            "bullish"
          elsif adx > 25 && ema_fast < ema_slow
            "bearish"
          else
            "choppy"
          end

        { trend:, rsi:, adx: }
      end
    end
  end
end
