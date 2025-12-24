# frozen_string_literal: true

require "date"

module Vyapari
  module Tools
    # Tool for fetching intraday price history
    class FetchIntradayHistory < Base
      def self.name = "fetch_intraday_history"

      def self.schema
        {
          type: "function",
          function: {
            name: name,
            description: "Fetches intraday price history for a symbol. Valid exchange_segment values: NSE_FNO, NSE_EQ, BSE_FNO, BSE_EQ, NSE_CURRENCY, BSE_CURRENCY, MCX_COMM, IDX_I",
            parameters: {
              type: "object",
              properties: {
                security_id: { type: "string" },
                exchange_segment: {
                  type: "string",
                  description: "Exchange segment (NSE_FNO, NSE_EQ, BSE_FNO, BSE_EQ, etc.). Common abbreviations: NFO->NSE_FNO, BFO->BSE_FNO"
                },
                instrument: { type: "string" },
                interval: { type: "string" }
              },
              required: %w[security_id exchange_segment instrument interval]
            }
          }
        }
      end

      def call(p)
        exchange_segment = ExchangeSegmentHelper.normalize(p["exchange_segment"])

        DhanHQ::Models::HistoricalData.intraday(
          security_id: p["security_id"],
          exchange_segment: exchange_segment,
          instrument: p["instrument"],
          interval: p["interval"],
          from_date: (Date.today - 7).to_s,
          to_date: Date.today.to_s
        )
      end
    end
  end
end
