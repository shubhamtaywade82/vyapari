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
            description: "STEP 1: Finds trading instrument by exchange segment and symbol. MUST be called first, ONE AT A TIME. For indices (NIFTY, BANKNIFTY, SENSEX), use exchange_segment='IDX_I'. For stocks, use NSE_EQ or BSE_EQ. Returns security_id, exchange_segment, and instrument (use this 'instrument' field for fetch_intraday_history).",
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
        symbol = params["symbol"].to_s.upcase
        exchange_segment = params["exchange_segment"].to_s

        # Auto-correct common index symbols to use IDX_I
        index_symbols = %w[NIFTY BANKNIFTY SENSEX NIFTY50 BANKNIFTY50]
        exchange_segment = "IDX_I" if index_symbols.include?(symbol) && exchange_segment != "IDX_I"

        exchange_segment = ExchangeSegmentHelper.normalize(exchange_segment)

        inst = DhanHQ::Models::Instrument.find(
          exchange_segment,
          symbol
        )

        raise "Instrument not found" unless inst

        {
          security_id: inst.security_id.to_s,
          exchange_segment: inst.exchange_segment,
          instrument: inst.instrument || inst.instrument_type,
          instrument_type: inst.instrument_type,
          symbol: symbol # Store original symbol for use in fetch_expiry_list and fetch_option_chain
        }
      end
    end
  end
end
