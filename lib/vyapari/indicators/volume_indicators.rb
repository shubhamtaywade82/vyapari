# frozen_string_literal: true

require_relative "technical_analysis_adapter"

module Vyapari
  module Indicators
    # Helper module for volume-based indicators
    # Uses TechnicalAnalysisAdapter to calculate volume indicators
    module VolumeIndicators
      # Calculate all volume indicators for given candles
      def self.calculate_all(candles)
        adapter = TechnicalAnalysisAdapter.new(candles)

        begin
          {
            obv: adapter.latest_obv,
            cmf: adapter.latest_cmf(period: 20),
            mfi: adapter.latest_mfi(period: 14),
            vroc: adapter.vroc(period: 12)&.last&.vroc,
            accumulation_distribution: adapter.accumulation_distribution&.last&.ad
          }
        rescue StandardError => e
          # Return nil values if calculation fails
          {
            obv: nil,
            cmf: nil,
            mfi: nil,
            vroc: nil,
            accumulation_distribution: nil
          }
        end
      end

      # Get Money Flow Index (MFI) - Volume-weighted RSI
      # Returns: Float (0-100) or nil if insufficient data
      def self.mfi(candles, period: 14)
        adapter = TechnicalAnalysisAdapter.new(candles)
        adapter.latest_mfi(period: period)
      end

      # Get Chaikin Money Flow (CMF) - Volume-weighted accumulation/distribution
      # Returns: Float (-1 to +1) or nil if insufficient data
      def self.cmf(candles, period: 20)
        adapter = TechnicalAnalysisAdapter.new(candles)
        adapter.latest_cmf(period: period)
      end

      # Get On-Balance Volume (OBV) - Cumulative volume indicator
      # Returns: Float or nil if insufficient data
      def self.obv(candles)
        adapter = TechnicalAnalysisAdapter.new(candles)
        adapter.latest_obv
      end

      # Determine volume trend based on multiple indicators
      # Returns: "bullish", "bearish", or "neutral"
      def self.volume_trend(candles)
        begin
          adapter = TechnicalAnalysisAdapter.new(candles)

          mfi_value = adapter.latest_mfi(period: 14)
          cmf_value = adapter.latest_cmf(period: 20)
          obv_trend = obv_trend_direction(adapter.obv)

          # Combine signals
          bullish_signals = 0
          bearish_signals = 0

          # MFI signals (>50 = bullish, <50 = bearish)
          if mfi_value
            if mfi_value > 50
              bullish_signals += 1
            elsif mfi_value < 50
              bearish_signals += 1
            end
          end

          # CMF signals (>0 = bullish, <0 = bearish)
          if cmf_value
            if cmf_value > 0
              bullish_signals += 1
            elsif cmf_value < 0
              bearish_signals += 1
            end
          end

          # OBV trend
          if obv_trend == "up"
            bullish_signals += 1
          elsif obv_trend == "down"
            bearish_signals += 1
          end

          # Determine overall trend
          if bullish_signals > bearish_signals
            "bullish"
          elsif bearish_signals > bullish_signals
            "bearish"
          else
            "neutral"
          end
        rescue StandardError
          # If volume indicators fail, return neutral
          "neutral"
        end
      end

      private_class_method def self.obv_trend_direction(obv_values)
        return "neutral" if obv_values.nil? || obv_values.length < 2

        # Get last few OBV values to determine trend
        recent = obv_values.last(5).map do |v|
          v.is_a?(Hash) ? v[:obv] || v["obv"] : v.obv
        rescue StandardError
          v
        end
        return "neutral" if recent.length < 2

        # Simple trend: compare last two values
        if recent.last > recent.first
          "up"
        elsif recent.last < recent.first
          "down"
        else
          "neutral"
        end
      end
    end
  end
end
