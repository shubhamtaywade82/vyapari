# frozen_string_literal: true

# Strike Selection Decision Framework
# Deterministic rules for selecting option strikes based on market structure

module Vyapari
  module Options
    module StrikeSelectionFramework
      # Decision framework for strike selection
      # Based on: Direction → Regime → Momentum → Volatility → Time

      # Determine strike distance based on market regime
      # @param regime [String] Market regime from HTF analysis
      # @return [Symbol] :atm, :one_otm, :no_trade
      def self.strike_distance_from_regime(regime)
        case regime.to_s.upcase
        when "TREND_DAY", "VOLATILITY_EXPANSION"
          :one_otm # Strong trend/expansion allows 1 step OTM
        when "NORMAL_TREND", "TREND"
          :atm # Normal trend = ATM only
        when "RANGE", "CHOP"
          :no_trade # Range = NO_TRADE (options die in ranges)
        else
          :no_trade
        end
      end

      # Determine strike preference based on momentum
      # @param momentum [String] Momentum strength from MTF
      # @return [Symbol] :atm_otm, :atm, :no_trade
      def self.strike_preference_from_momentum(momentum)
        case momentum.to_s.upcase
        when "STRONG"
          :atm_otm # Strong momentum allows slight OTM
        when "MODERATE", "NORMAL"
          :atm # Moderate momentum = ATM only
        when "WEAK"
          :no_trade # Weak momentum = NO_TRADE (cheap OTM is trap)
        else
          :no_trade
        end
      end

      # Determine strike allowance based on volatility
      # @param vol_state [String] Volatility state (expanding, average, contracting)
      # @return [Symbol] :allow_otm, :atm_only, :no_trade
      def self.strike_allowance_from_volatility(vol_state)
        case vol_state.to_s.downcase
        when "expanding", "high"
          :allow_otm # Expanding vol allows OTM
        when "average", "normal"
          :atm_only # Average vol = ATM only
        when "contracting", "low"
          :no_trade # Contracting vol = NO_TRADE (no premium expansion)
        else
          :atm_only # Default to ATM if unclear
        end
      end

      # Determine strike allowance based on time of day
      # @param current_time [Time] Current time
      # @return [Symbol] :atm_otm, :atm, :itm_atm, :no_new_trades
      def self.strike_allowance_from_time(current_time = Time.now)
        hour = current_time.hour
        minute = current_time.min
        time_minutes = hour * 60 + minute

        # Market hours: 9:15 AM to 3:30 PM IST
        # 9:20 = 560 minutes, 11:30 = 690 minutes, 13:30 = 810 minutes, 14:45 = 885 minutes

        if time_minutes >= 560 && time_minutes <= 690
          # 9:20 - 11:30: Early session, allow ATM/1OTM
          :atm_otm
        elsif time_minutes > 690 && time_minutes <= 810
          # 11:30 - 13:30: Mid session, ATM only
          :atm
        elsif time_minutes > 810 && time_minutes <= 885
          # 13:30 - 14:45: Late session, ITM/ATM only (theta decay)
          :itm_atm
        elsif time_minutes > 885
          # After 14:45: NO NEW TRADES (theta decay too high)
          :no_new_trades
        else
          # Before 9:20: Pre-market, ATM only
          :atm
        end
      end

      # Filter strikes based on all criteria
      # @param candidates [Array] Array of strike candidates from option chain
      # @param spot_price [Float] Current spot price
      # @param direction [String] BULLISH or BEARISH
      # @param regime [String] Market regime
      # @param momentum [String] Momentum strength
      # @param vol_state [String] Volatility state
      # @param current_time [Time] Current time
      # @return [Array] Filtered strike candidates
      def self.filter_strikes(candidates:, spot_price:, direction:, regime:, momentum:, vol_state: "average", current_time: Time.now)
        # Step 1: Direction → CE or PE
        option_type = direction.to_s.upcase == "BULLISH" ? "CE" : "PE"

        # Step 2: Regime → Distance
        regime_distance = strike_distance_from_regime(regime)
        return [] if regime_distance == :no_trade

        # Step 3: Momentum → Preference
        momentum_pref = strike_preference_from_momentum(momentum)
        return [] if momentum_pref == :no_trade

        # Step 4: Volatility → Allowance
        vol_allowance = strike_allowance_from_volatility(vol_state)
        return [] if vol_allowance == :no_trade

        # Step 5: Time → Allowance
        time_allowance = strike_allowance_from_time(current_time)
        return [] if time_allowance == :no_new_trades

        # Step 6: Find ATM strike
        atm_strike = candidates.min_by { |c| (c[:strike] || c["strike"] || 0) - spot_price.abs }

        # Step 7: Filter candidates based on all rules
        filtered = []

        candidates.each do |contract|
          strike = contract[:strike] || contract["strike"] || 0
          type = contract[:type] || contract["type"] || ""
          next unless type.upcase == option_type

          # Calculate moneyness
          moneyness = if strike == spot_price
                        "ATM"
                      elsif (direction == "BULLISH" && strike < spot_price) || (direction == "BEARISH" && strike > spot_price)
                        "ITM"
                      else
                        "OTM"
                      end

          # Apply filters
          allowed = true

          # Regime filter
          case regime_distance
          when :atm
            allowed = false unless moneyness == "ATM"
          when :one_otm
            strike_diff = (strike - spot_price).abs
            atm_diff = (atm_strike[:strike] || atm_strike["strike"] || 0) - spot_price.abs
            allowed = false if strike_diff > (atm_diff * 2) # Only allow ±1 strike from ATM
          end

          # Momentum filter
          case momentum_pref
          when :atm
            allowed = false unless moneyness == "ATM"
          when :atm_otm
            allowed = false if moneyness == "ITM" # Prefer ATM/OTM, not ITM
          end

          # Volatility filter
          if vol_allowance == :atm_only
            allowed = false unless moneyness == "ATM"
          end

          # Time filter
          case time_allowance
          when :atm
            allowed = false unless moneyness == "ATM"
          when :itm_atm
            allowed = false if moneyness == "OTM" # Late session: ITM/ATM only
          end

          # Limit to ±1-2 strikes around ATM
          strike_diff = (strike - spot_price).abs
          atm_strike_value = atm_strike[:strike] || atm_strike["strike"] || spot_price
          atm_diff = (atm_strike_value - spot_price).abs
          allowed = false if strike_diff > (atm_diff * 3) # Max ±2 strikes

          filtered << contract.merge(moneyness: moneyness) if allowed
        end

        # Sort by proximity to ATM
        filtered.sort_by { |c| (c[:strike] || c["strike"] || 0) - spot_price.abs }
      end

      # Generate strike selection reason
      # @param regime [String] Market regime
      # @param momentum [String] Momentum
      # @param vol_state [String] Volatility state
      # @param time_allowance [Symbol] Time allowance
      # @return [String] Human-readable reason
      def self.generate_reason(regime:, momentum:, vol_state:, time_allowance:)
        reasons = []

        reasons << "Regime: #{regime} allows #{strike_distance_from_regime(regime)}"
        reasons << "Momentum: #{momentum} suggests #{strike_preference_from_momentum(momentum)}"
        reasons << "Volatility: #{vol_state} allows #{strike_allowance_from_volatility(vol_state)}"
        reasons << "Time: #{time_allowance} restriction applies"

        reasons.join("; ")
      end
    end
  end
end

