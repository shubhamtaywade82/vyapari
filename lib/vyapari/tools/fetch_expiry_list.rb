# frozen_string_literal: true

module Vyapari
  module Tools
    # Tool for fetching available expiry dates for an instrument
    class FetchExpiryList < Base
      def self.name = "fetch_expiry_list"

      def self.schema
        {
          type: "function",
          function: {
            name: name,
            description: "STEP 4: Fetches available expiry dates for the instrument. MUST be called after find_instrument. Returns list of expiry dates. Used by fetch_option_chain to select the nearest valid expiry.",
            parameters: {
              type: "object",
              properties: {},
              required: []
            }
          }
        }
      end

      def call(p)
        # Get parameters from context (injected by agent)
        underlying_seg = p["underlying_seg"] || p[:underlying_seg] || "IDX_I"
        underlying_scrip = p["underlying_scrip"] || p[:underlying_scrip]
        symbol = p["symbol"] || p[:symbol]

        # Try OptionChain.fetch_expiry_list first (as shown in user's example)
        if underlying_scrip
          underlying_scrip = underlying_scrip.to_i
          raise "Invalid underlying_scrip: must be a number" if underlying_scrip.zero?

          begin
            expiries = DhanHQ::Models::OptionChain.fetch_expiry_list(
              underlying_seg: underlying_seg,
              underlying_scrip: underlying_scrip
            )
            raise "No expiries available" if expiries.nil? || expiries.empty?
            return expiries
          rescue StandardError => e
            # If OptionChain.fetch_expiry_list fails, fall back to instrument.expiry_list
            # This happens if API endpoint has issues or authentication problems
          end
        end

        # Fallback: Use instrument.expiry_list method (same as fetch_option_chain uses)
        # Need symbol to find instrument (Instrument.find takes exchange_segment and symbol, not security_id)
        if symbol
          symbol = symbol.to_s.upcase
          underlying = DhanHQ::Models::Instrument.find(underlying_seg, symbol)
          raise "Underlying not found for symbol: #{symbol}" unless underlying
          expiries = underlying.expiry_list || []
        else
          raise "Missing required parameters: need either underlying_scrip (for OptionChain.fetch_expiry_list) or symbol (for instrument.expiry_list fallback)"
        end

        raise "No expiries available" if expiries.nil? || expiries.empty?

        # Return expiries - agent will handle expiry_passed logic
        expiries
      end
    end
  end
end

