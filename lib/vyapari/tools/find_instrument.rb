# frozen_string_literal: true

module Vyapari
  module Tools
    # Tool for finding trading instruments
    class FindInstrument < Base
      def self.name = "find_instrument"

      def self.schema
        {
          type: "function",
          function: {
            name: name,
            description: "Finds trading instrument by exchange segment and symbol. Valid exchange_segment values: NSE_FNO, NSE_EQ, BSE_FNO, BSE_EQ, NSE_CURRENCY, BSE_CURRENCY, MCX_COMM, IDX_I",
            parameters: {
              type: "object",
              properties: {
                exchange_segment: {
                  type: "string",
                  description: "Exchange segment (NSE_FNO, NSE_EQ, BSE_FNO, BSE_EQ, etc.). Common abbreviations: NFO->NSE_FNO, BFO->BSE_FNO"
                },
                symbol: { type: "string" }
              },
              required: %w[exchange_segment symbol]
            }
          }
        }
      end

      def call(params)
        exchange_segment = ExchangeSegmentHelper.normalize(params["exchange_segment"])

        inst = DhanHQ::Models::Instrument.find(
          exchange_segment,
          params["symbol"]
        )

        raise "Instrument not found" unless inst

        {
          security_id: inst.security_id,
          exchange_segment: inst.exchange_segment,
          instrument_type: inst.instrument_type
        }
      end
    end
  end
end
