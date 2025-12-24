# frozen_string_literal: true

module Vyapari
  module Tools
    # Helper for normalizing exchange segment values
    module ExchangeSegmentHelper
      EXCHANGE_SEGMENT_MAP = {
        "NFO" => "NSE_FNO",
        "NSE" => "NSE_EQ",
        "BSE" => "BSE_EQ",
        "BFO" => "BSE_FNO",
        "MCX" => "MCX_COMM",
        "NSE_EQ" => "NSE_EQ",
        "NSE_FNO" => "NSE_FNO",
        "NSE_CURRENCY" => "NSE_CURRENCY",
        "BSE_EQ" => "BSE_EQ",
        "BSE_FNO" => "BSE_FNO",
        "BSE_CURRENCY" => "BSE_CURRENCY",
        "MCX_COMM" => "MCX_COMM",
        "IDX_I" => "IDX_I"
      }.freeze

      VALID_SEGMENTS = %w[
        NSE_EQ NSE_FNO NSE_CURRENCY
        BSE_EQ BSE_FNO BSE_CURRENCY
        MCX_COMM IDX_I
      ].freeze

      def self.normalize(segment)
        normalized = EXCHANGE_SEGMENT_MAP[segment.to_s.upcase]
        normalized || segment
      end

      def self.valid?(segment)
        VALID_SEGMENTS.include?(segment.to_s)
      end
    end
  end
end
