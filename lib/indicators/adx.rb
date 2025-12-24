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

      def calculate(_candles)
        raise NotImplementedError
      end

      private

      attr_reader :period
    end
  end
end
