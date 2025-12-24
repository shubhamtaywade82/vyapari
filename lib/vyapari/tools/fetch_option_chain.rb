# frozen_string_literal: true

require "date"
require "time"

module Vyapari
  module Tools
    # Tool for fetching option chain data
    class FetchOptionChain < Base
      def self.name = "fetch_option_chain"

      def self.schema
        {
          type: "function",
          function: {
            name: name,
            description: "Fetches option chain data for index options (NIFTY, BANKNIFTY, etc.)",
            parameters: {
              type: "object",
              properties: {
                symbol: { type: "string" },
                expiry: { type: "string" },
                trend: { type: "string", enum: %w[bullish bearish] }
              },
              required: %w[symbol expiry trend]
            }
          }
        }
      end

      def call(p)
        # 1️⃣ Underlying index
        underlying = DhanHQ::Models::Instrument.find("IDX_I", p["symbol"])
        raise "Underlying not found" unless underlying

        # Get expiry - use provided expiry or fetch nearest available
        expiry = p["expiry"].to_s.strip
        if expiry.empty?
          # Fetch available expiries and use the nearest one
          expiries = underlying.expiry_list || []
          raise "No expiries available for #{p["symbol"]}" if expiries.empty?

          # Check if first expiry has passed (after 4 PM on expiry day)
          first_expiry = expiries.first
          if expiry_passed?(first_expiry)
            # Use second expiry if first has passed
            raise "No valid expiries available for #{p["symbol"]}" if expiries.length < 2

            expiry = expiries[1]
          else
            expiry = first_expiry
          end
        elsif expiry_passed?(expiry)
          # If provided expiry has passed, fetch available expiries and use next valid one
          expiries = underlying.expiry_list || []
          raise "No expiries available for #{p["symbol"]}" if expiries.empty?

          # Find the next valid expiry after the provided one
          valid_expiries = expiries.reject { |e| expiry_passed?(e) }
          raise "No valid expiries available for #{p["symbol"]}" if valid_expiries.empty?

          expiry = valid_expiries.first
        end

        chain = underlying.option_chain(expiry: expiry)

        spot   = chain["last_price"].to_f
        oc     = chain["oc"]
        strikes = oc.keys.map(&:to_f).sort

        raise "Empty option chain" if strikes.empty?

        # 3️⃣ ATM
        atm_strike = strikes.min_by { |s| (s - spot).abs }
        atm_index  = strikes.index(atm_strike)

        # 4️⃣ ATM+1
        otm_strike =
          if p["trend"] == "bullish"
            strikes[atm_index + 1]
          else
            strikes[atm_index - 1]
          end

        # 5️⃣ Side
        side = p["trend"] == "bullish" ? "ce" : "pe"

        # 6️⃣ Extract contracts
        selected = [atm_strike, otm_strike].compact.map do |strike|
          oc[format("%.6f", strike)][side]
        end

        {
          spot_price: spot,
          atm_strike: atm_strike,
          otm_strike: otm_strike,
          side: side.upcase,
          contracts: selected
        }
      end

      private

      def expiry_passed?(expiry_date_str)
        return false if expiry_date_str.nil? || expiry_date_str.empty?

        expiry_date = Date.parse(expiry_date_str)
        today = Date.today
        current_time = Time.now

        # Check if expiry is today and it's past 4 PM (16:00)
        if expiry_date == today
          current_time.hour >= 16
        else
          # Check if expiry date is in the past
          expiry_date < today
        end
      rescue Date::Error
        false
      end
    end
  end
end
