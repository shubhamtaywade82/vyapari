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
            description: "STEP 5: Fetches option chain data for index options. MUST be called after analyze_trend returns 'bullish' or 'bearish'. DO NOT call if trend is 'avoid'. ALL parameters (symbol, expiry, trend) are automatically injected from context - call with empty parameters: {}.",
            parameters: {
              type: "object",
              properties: {},
              required: []
            }
          }
        }
      end

      def call(p)
        # Validate required parameters
        symbol = p["symbol"] || p[:symbol]
        trend = p["trend"] || p[:trend]
        expiry = p["expiry"] || p[:expiry]

        raise ArgumentError, "symbol parameter is required and cannot be empty. Use the 'instrument' field from find_instrument result." if symbol.nil? || symbol.to_s.strip.empty?
        raise ArgumentError, "trend parameter is required (must be 'bullish' or 'bearish')" if trend.nil? || trend.to_s.strip.empty?

        # Normalize trend
        trend = trend.to_s.downcase.strip
        if trend == "avoid"
          raise ArgumentError, "Cannot fetch option chain when trend is 'avoid'. Call recommend_trade with trend='avoid' instead to get NO_TRADE recommendation."
        end
        raise ArgumentError, "trend must be 'bullish' or 'bearish', got: #{trend}" unless %w[bullish bearish].include?(trend)

        # Get underlying_seg and underlying_scrip from context (injected by agent)
        # For indices, always use IDX_I
        underlying_seg = p["underlying_seg"] || p[:underlying_seg] || "IDX_I"
        underlying_scrip = p["underlying_scrip"] || p[:underlying_scrip]

        # If not provided, try to get from symbol (fallback)
        if !underlying_scrip
          symbol_str = symbol.to_s.upcase
          underlying = DhanHQ::Models::Instrument.find("IDX_I", symbol_str)
          raise "Underlying not found for symbol: #{symbol_str}" unless underlying
          underlying_seg = "IDX_I"
          underlying_scrip = underlying.security_id.to_i
        else
          underlying_scrip = underlying_scrip.to_i
          raise "Invalid underlying_scrip: must be a number" if underlying_scrip.zero?
        end

        # Get expiry - use provided expiry (should be from context)
        expiry = expiry.to_s.strip if expiry
        raise "Missing expiry parameter" if expiry.nil? || expiry.empty?

        # Validate expiry hasn't passed (if it has, should have been handled in fetch_expiry_list)
        if expiry_passed?(expiry)
          # Fetch available expiries and use next valid one
          expiries = DhanHQ::Models::OptionChain.fetch_expiry_list(
            underlying_seg: underlying_seg,
            underlying_scrip: underlying_scrip
          )
          raise "No expiries available" if expiries.nil? || expiries.empty?

          # Find the next valid expiry after the provided one
          valid_expiries = expiries.reject { |e| expiry_passed?(e) }
          raise "No valid expiries available" if valid_expiries.empty?

          expiry = valid_expiries.first
        end

        # Use OptionChain.fetch API (as shown in user's example)
        begin
          chain = DhanHQ::Models::OptionChain.fetch(
            underlying_seg: underlying_seg,
            underlying_scrip: underlying_scrip,
            expiry: expiry
          )

          # Validate response is a Hash (handles holidays/errors where API returns HTML)
          unless chain.is_a?(Hash)
            raise "Invalid response format: expected Hash, got #{chain.class}. API may have returned HTML/error page (e.g., 502 Bad Gateway on holidays)."
          end
        rescue StandardError => e
          # If OptionChain.fetch fails (e.g., holiday returns HTML, 502 Bad Gateway, etc.)
          error_msg = "Failed to fetch option chain for expiry #{expiry}: #{e.message}"
          error_msg += " This may be due to market holidays or API issues. Try a different expiry date."
          raise error_msg
        end

        spot   = chain["last_price"]&.to_f || chain[:last_price]&.to_f
        oc     = chain["oc"] || chain[:oc]

        raise "Invalid option chain response: missing 'last_price' or 'oc' fields" if spot.nil? || oc.nil?

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
        side = trend == "bullish" ? "ce" : "pe"
        raise "Invalid side calculated: #{side}" if side.nil? || side.empty?

        # 6️⃣ Extract contracts
        selected = [atm_strike, otm_strike].compact.map do |strike|
          strike_key = format("%.6f", strike)
          oc[strike_key]&.dig(side)
        end.compact

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
