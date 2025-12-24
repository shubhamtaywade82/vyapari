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

      def calculate(_prices)
        raise NotImplementedError
      end

      private

      attr_reader :period
    end
  end
end
