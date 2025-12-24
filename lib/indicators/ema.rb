# frozen_string_literal: true

module Vyapari
  module Indicators
    # Exponential Moving Average (EMA) indicator
    class EMA
      def self.calculate(prices, period)
        new(period: period).calculate(prices)
      end

      def initialize(period: 20)
        @period = period
      end

      def calculate(prices)
        return prices.last.to_f if prices.length < @period # Return last price if not enough data

        # Calculate smoothing factor
        multiplier = 2.0 / (@period + 1.0)

        # Start with SMA for first value
        ema = prices.first(@period).sum.to_f / @period

        # Calculate EMA for remaining values
        prices[@period..-1].each do |price|
          ema = (price.to_f * multiplier) + (ema * (1.0 - multiplier))
        end

        ema.round(2)
      end

      private

      attr_reader :period
    end
  end
end
