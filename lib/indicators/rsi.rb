# frozen_string_literal: true

module Vyapari
  module Indicators
    # Relative Strength Index (RSI) indicator
    class RSI
      def self.calculate(prices, period: 14)
        new(period: period).calculate(prices)
      end

      def initialize(period: 14)
        @period = period
      end

      def calculate(prices)
        return 50.0 if prices.length < @period + 1 # Default neutral RSI if not enough data

        gains = []
        losses = []

        # Calculate price changes
        (1...prices.length).each do |i|
          change = prices[i] - prices[i - 1]
          if change > 0
            gains << change
            losses << 0
          else
            gains << 0
            losses << change.abs
          end
        end

        return 50.0 if gains.empty? || losses.empty?

        # Calculate average gain and loss over period
        avg_gain = gains.last(@period).sum.to_f / @period
        avg_loss = losses.last(@period).sum.to_f / @period

        return 50.0 if avg_loss.zero? # Avoid division by zero

        # Calculate RS and RSI
        rs = avg_gain / avg_loss
        rsi = 100.0 - (100.0 / (1.0 + rs))

        rsi.round(2)
      end

      private

      attr_reader :period
    end
  end
end
