# frozen_string_literal: true

require "json"
require_relative "../indicators/volume_indicators"

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
            description: "STEP 3: Analyzes market trends based on candle data from fetch_intraday_history. MUST be called after fetch_intraday_history. Uses RSI, ADX, EMA (price-based) and MFI, CMF, OBV (volume-based) indicators. Returns trend: 'bullish', 'bearish', or 'avoid'. If 'avoid', do NOT call fetch_option_chain. ALL parameters (candles) are automatically injected from context - call with empty parameters: {}.",
            parameters: {
              type: "object",
              properties: {},
              required: []
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

        # Calculate price-based indicators (using existing custom implementations)
        rsi = Indicators::RSI.calculate(closes) # Range: 0-100 (momentum)
        adx = Indicators::ADX.calculate(candles_data) # Range: 0-100 (trend strength)
        ema_fast = Indicators::EMA.calculate(closes, 9) # Short-term trend (9 periods)
        ema_slow = Indicators::EMA.calculate(closes, 21) # Long-term trend (21 periods)

        # Calculate volume-based indicators (using new TechnicalAnalysisAdapter)
        # Wrap in error handling - if volume indicators fail, continue with price-based analysis
        begin
          volume_indicators = Indicators::VolumeIndicators.calculate_all(candles_data)
          volume_trend = Indicators::VolumeIndicators.volume_trend(candles_data)
        rescue StandardError => e
          # If volume indicators fail, use neutral volume trend and empty indicators
          # This allows the analysis to continue with price-based indicators only
          volume_indicators = { obv: nil, cmf: nil, mfi: nil, vroc: nil, accumulation_distribution: nil }
          volume_trend = "neutral"
          # Log the error but don't fail the entire analysis
          warn "Volume indicators calculation failed: #{e.message}" if defined?(warn)
        end

        # Trend determination logic:
        # - ADX > 25: Strong trend exists
        # - ADX ≤ 25: Weak/choppy market → AVOID
        # - EMA Fast > Slow: Uptrend (bullish)
        # - EMA Fast < Slow: Downtrend (bearish)
        # - Volume confirmation: Use volume trend to confirm price trend
        price_trend =
          if adx > 25 && ema_fast > ema_slow
            "bullish"
          elsif adx > 25 && ema_fast < ema_slow
            "bearish"
          else
            "avoid" # ADX ≤ 25 or unclear EMA relationship = choppy market
          end

        # Use volume to confirm or weaken price trend
        trend =
          if price_trend == "avoid"
            "avoid" # Price trend is already weak
          elsif price_trend == "bullish" && volume_trend == "bullish"
            "bullish" # Strong confirmation
          elsif price_trend == "bearish" && volume_trend == "bearish"
            "bearish" # Strong confirmation
          elsif price_trend == "bullish" && volume_trend == "bearish"
            "avoid" # Volume divergence - weak signal
          elsif price_trend == "bearish" && volume_trend == "bullish"
            "avoid" # Volume divergence - weak signal
          else
            price_trend # Use price trend if volume is neutral
          end

        pp trend
        pp rsi
        pp adx
        pp ema_fast
        pp ema_slow
        pp volume_trend
        pp volume_indicators
        pp trend == "avoid" ? "Avoid trading - market is choppy" : "Market trend is #{trend.upcase}"

        {
          trend: trend,
          rsi: rsi,
          adx: adx,
          ema_fast: ema_fast,
          ema_slow: ema_slow,
          volume_trend: volume_trend,
          mfi: volume_indicators[:mfi],
          cmf: volume_indicators[:cmf],
          obv: volume_indicators[:obv],
          recommendation: trend == "avoid" ? "Avoid trading - market is choppy" : "Market trend is #{trend.upcase}"
        }
      end
    end
  end
end
