# frozen_string_literal: true

module Vyapari
  module Indicators
    # Average Directional Index (ADX) indicator
    class ADX
      def self.calculate(candles, period: 14)
        new(period: period).calculate(candles)
      end

      def initialize(period: 14)
        @period = period
      end

      def calculate(candles)
        return 0.0 if candles.length < @period * 2 # Need enough data for ADX

        # Extract high, low, close arrays
        highs = candles.map { |c| (c["high"] || c[:high]).to_f }
        lows = candles.map { |c| (c["low"] || c[:low]).to_f }
        closes = candles.map { |c| (c["close"] || c[:close]).to_f }

        # Calculate True Range (TR) and Directional Movement (+DM, -DM)
        trs = []
        plus_dms = []
        minus_dms = []

        (1...candles.length).each do |i|
          # True Range
          tr = [
            highs[i] - lows[i],
            (highs[i] - closes[i - 1]).abs,
            (lows[i] - closes[i - 1]).abs
          ].max
          trs << tr

          # Directional Movement
          plus_dm = highs[i] - highs[i - 1]
          minus_dm = lows[i - 1] - lows[i]

          plus_dm = 0 if plus_dm < 0 || plus_dm < minus_dm
          minus_dm = 0 if minus_dm < 0 || minus_dm < plus_dm

          plus_dms << plus_dm
          minus_dms << minus_dm
        end

        return 0.0 if trs.length < @period

        # Calculate smoothed TR, +DM, -DM
        atr = trs.first(@period).sum.to_f / @period
        plus_di_sum = plus_dms.first(@period).sum.to_f / @period
        minus_di_sum = minus_dms.first(@period).sum.to_f / @period

        # Smooth remaining values using Wilder's smoothing
        (@period...trs.length).each do |i|
          atr = (atr * (@period - 1) + trs[i]) / @period
          plus_di_sum = (plus_di_sum * (@period - 1) + plus_dms[i]) / @period
          minus_di_sum = (minus_di_sum * (@period - 1) + minus_dms[i]) / @period
        end

        return 0.0 if atr.zero? # Avoid division by zero

        # Calculate +DI and -DI
        plus_di = 100.0 * (plus_di_sum / atr)
        minus_di = 100.0 * (minus_di_sum / atr)

        # Calculate DX
        di_sum = plus_di + minus_di
        return 0.0 if di_sum.zero?

        dx = 100.0 * ((plus_di - minus_di).abs / di_sum)

        # ADX is the smoothed DX (simplified - using current DX as approximation)
        # In full implementation, ADX would be smoothed over multiple periods
        dx.round(2)
      end

      private

      attr_reader :period
    end
  end
end
