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

      def calculate(_prices)
        raise NotImplementedError
      end

      private

      attr_reader :period
    end
  end
end
