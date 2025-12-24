# frozen_string_literal: true

module Vyapari
  module Indicators
    # SuperTrend indicator
    class SuperTrend
      def initialize(period: 10, multiplier: 3.0)
        @period = period
        @multiplier = multiplier
      end

      def calculate(_high_prices, _low_prices, _close_prices)
        raise NotImplementedError
      end

      private

      attr_reader :period, :multiplier
    end
  end
end
