# frozen_string_literal: true

require_relative "day_type_classifier"
require_relative "structure_analyzer"
require_relative "volatility_analyzer"
require_relative "momentum_analyzer"

module Vyapari
  module Options
    # Pre-trade gate: Boolean checklist that blocks weak trades
    # ALL conditions must pass for trade to be allowed
    class PreTradeGate
      def self.run(trend:, options:, candles_5m:, candles_15m:, current_time: Time.now, spot_price: nil)
        new(trend, options, candles_5m, candles_15m, current_time, spot_price).run
      end

      def initialize(trend, options, candles_5m, candles_15m, current_time, spot_price)
        @trend = trend.to_s.downcase
        @options = options
        @candles_5m = candles_5m
        @candles_15m = candles_15m
        @current_time = current_time
        @spot_price = spot_price
        @failed_gates = []
        @gate_results = {}
      end

      def run
        # Run all gates
        market_regime_ok = gate_market_regime
        time_ok = gate_time_window
        structure_ok = gate_structure
        volatility_ok = gate_volatility
        momentum_ok = gate_momentum_timing
        strike_ok = gate_strike_quality
        expected_move_ok = gate_expected_move
        risk_ok = gate_risk_feasibility

        allowed = market_regime_ok && time_ok && structure_ok && volatility_ok &&
                  momentum_ok && strike_ok && expected_move_ok && risk_ok

        {
          allowed: allowed,
          failed_gates: @failed_gates,
          reason: allowed ? nil : "Failed gates: #{@failed_gates.join(", ")}",
          gate_results: @gate_results,
          structure: @gate_results[:structure],
          volatility: @gate_results[:volatility],
          momentum: @gate_results[:momentum],
          time_window: @gate_results[:time_window],
          strike_quality: @gate_results[:strike_quality]
        }
      end

      private

      # A. Market Regime Gate
      def gate_market_regime
        return false unless @candles_15m

        begin
          day_type = DayTypeClassifier.classify(@candles_15m, @candles_5m)
        rescue StandardError => e
          # Handle insufficient data errors gracefully
          if e.message.include?("Not enough data") || e.message.include?("insufficient") || e.message.include?("period")
            @failed_gates << "market_regime"
            @gate_results[:market_regime] = {
              day_type: :unknown,
              error: "Insufficient data for day type classification: #{e.message}",
              allowed: false
            }
            return false
          end
          raise # Re-raise if it's a different error
        end

        invalid_types = %i[inside_day narrow_range choppy unknown]

        if invalid_types.include?(day_type)
          @failed_gates << "market_regime"
          @gate_results[:market_regime] = { day_type: day_type, allowed: false }
          return false
        end

        @gate_results[:market_regime] = { day_type: day_type, allowed: true }
        true
      end

      # B. Time Window Gate
      def gate_time_window
        hour = @current_time.hour
        minute = @current_time.min
        time_minutes = (hour * 60) + minute

        # Window 1: 10:30-13:00 (630-780 minutes)
        # Window 2: 13:45-14:30 (825-870 minutes)
        in_window1 = time_minutes >= 630 && time_minutes <= 780
        in_window2 = time_minutes >= 825 && time_minutes <= 870

        if in_window1 || in_window2
          @gate_results[:time_window] = { current_time: "#{hour}:#{minute.to_s.rjust(2, "0")}", allowed: true }
          return true
        end

        @failed_gates << "time_window"
        @gate_results[:time_window] = { current_time: "#{hour}:#{minute.to_s.rjust(2, "0")}", allowed: false }
        false
      end

      # C. Structure Gate
      def gate_structure
        return false unless @candles_5m

        begin
          structure_result = StructureAnalyzer.analyze(@candles_5m, @candles_15m)
        rescue StandardError => e
          # Handle insufficient data errors gracefully
          if e.message.include?("Not enough data") || e.message.include?("insufficient") || e.message.include?("period")
            @failed_gates << "structure"
            @gate_results[:structure] = {
              signal: :none,
              error: "Insufficient data for structure analysis: #{e.message}",
              allowed: false
            }
            return false
          end
          raise # Re-raise if it's a different error
        end

        valid_signals = %i[bos_with_displacement trap_failure_retest range_break_follow_through]

        if structure_result[:signal] == :none || !valid_signals.include?(structure_result[:signal])
          @failed_gates << "structure"
          @gate_results[:structure] = { signal: structure_result[:signal], allowed: false }
          return false
        end

        @gate_results[:structure] = {
          signal: structure_result[:signal],
          direction: structure_result[:direction],
          quality: structure_result[:quality],
          allowed: true
        }
        true
      end

      # D. Volatility Gate
      def gate_volatility
        return false unless @candles_5m

        volatility_result = VolatilityAnalyzer.analyze(@candles_5m, current_time: @current_time)

        unless volatility_result[:expanding]
          @failed_gates << "volatility"
          @gate_results[:volatility] = {
            expanding: false,
            current_atr: volatility_result[:current_atr],
            median_atr: volatility_result[:median_atr],
            slope: volatility_result[:slope],
            allowed: false
          }
          return false
        end

        @gate_results[:volatility] = {
          expanding: true,
          current_atr: volatility_result[:current_atr],
          median_atr: volatility_result[:median_atr],
          slope: volatility_result[:slope],
          expansion_ratio: volatility_result[:expansion_ratio],
          allowed: true
        }
        true
      end

      # E. Momentum Timing Gate
      def gate_momentum_timing
        return false unless @candles_5m

        spot = @spot_price || extract_spot_from_options || extract_spot_from_candles
        return false unless spot

        delta = extract_delta_from_options || 0.45 # Default delta

        begin
          momentum_result = MomentumAnalyzer.analyze(@candles_5m, spot, delta)
        rescue StandardError => e
          # Handle insufficient data errors gracefully
          if e.message.include?("Not enough data") || e.message.include?("insufficient") || e.message.include?("period")
            @failed_gates << "momentum_timing"
            @gate_results[:momentum] = {
              error: "Insufficient data for momentum analysis: #{e.message}",
              allowed: false
            }
            return false
          end
          raise # Re-raise if it's a different error
        end

        # Expected early move must be ≥ ₹4 premium within 2 candles
        if momentum_result[:expected_premium] < 4.0
          @failed_gates << "momentum_timing"
          @gate_results[:momentum] = {
            expected_premium: momentum_result[:expected_premium],
            expected_index_move: momentum_result[:expected_index_move],
            allowed: false
          }
          return false
        end

        @gate_results[:momentum] = {
          expected_premium: momentum_result[:expected_premium],
          expected_index_move: momentum_result[:expected_index_move],
          body_percent: momentum_result[:body_percent],
          follow_through: momentum_result[:follow_through],
          momentum_quality: momentum_result[:momentum_quality],
          allowed: true
        }
        true
      end

      # F. Strike Quality Gate
      def gate_strike_quality
        return false unless @options

        contracts = extract_contracts(@options)
        return false if contracts.empty?

        contract = contracts.first

        # Extract delta
        delta = (contract["delta"] || contract[:delta] || 0).to_f

        # Extract bid/ask for spread calculation
        bid = (contract["bid"] || contract[:bid] || contract["last_price"] || contract[:last_price] || 0).to_f
        ask = (contract["ask"] || contract[:ask] || contract["last_price"] || contract[:last_price] || 0).to_f
        mid_price = (bid + ask) / 2.0

        # Calculate spread %
        spread_pct = mid_price > 0 ? ((ask - bid) / mid_price) * 100 : 100

        # Extract strike and spot for distance calculation
        strike = (contract["strike"] || contract[:strike] || 0).to_f
        spot = @spot_price || extract_spot_from_options || 0.0

        # Calculate strike distance from ATM
        strike_distance = spot > 0 ? ((strike - spot) / spot * 100).abs : 100

        # Validate: delta 0.40-0.55, spread <1%, strike distance ≤ ±1%
        delta_ok = delta >= 0.40 && delta <= 0.55
        spread_ok = spread_pct < 1.0
        strike_ok = strike_distance <= 1.0

        if !delta_ok || !spread_ok || !strike_ok
          @failed_gates << "strike_quality"
          @gate_results[:strike_quality] = {
            delta: delta,
            spread_pct: spread_pct,
            strike_distance: strike_distance,
            allowed: false
          }
          return false
        end

        @gate_results[:strike_quality] = {
          delta: delta,
          spread_pct: spread_pct,
          strike_distance: strike_distance,
          allowed: true
        }
        true
      end

      # G. Expected Move Gate
      def gate_expected_move
        return false unless @candles_5m

        spot = @spot_price || extract_spot_from_options || extract_spot_from_candles
        return false unless spot

        delta = extract_delta_from_options || 0.45

        momentum_result = MomentumAnalyzer.analyze(@candles_5m, spot, delta)

        # Expected premium must be ≥ 12
        expected_premium = momentum_result[:expected_premium]

        if expected_premium < 12.0
          @failed_gates << "expected_move"
          @gate_results[:expected_move] = {
            expected_premium: expected_premium,
            expected_index_move: momentum_result[:expected_index_move],
            delta: delta,
            allowed: false
          }
          return false
        end

        @gate_results[:expected_move] = {
          expected_premium: expected_premium,
          expected_index_move: momentum_result[:expected_index_move],
          delta: delta,
          allowed: true
        }
        true
      end

      # H. Risk Feasibility Gate
      def gate_risk_feasibility
        return false unless @options

        contracts = extract_contracts(@options)
        return false if contracts.empty?

        contract = contracts.first
        premium = (contract["last_price"] || contract[:last_price] ||
                   contract["average_price"] || contract[:average_price] || 0).to_f

        return false if premium.zero?

        # Calculate max loss per trade (assuming 4 lots, 65% stop loss)
        max_loss_per_lot = premium * 0.65
        max_loss_4_lots = max_loss_per_lot * 4

        # Expected avg win (assuming 40% win rate, 140% target)
        expected_win_per_lot = premium * 0.4 # 40% move
        expected_avg_win = expected_win_per_lot * 4 * 0.4 # 40% win rate

        # Max loss must be ≤ 1.5 × expected avg win
        if max_loss_4_lots > (expected_avg_win * 1.5)
          @failed_gates << "risk_feasibility"
          @gate_results[:risk_feasibility] = {
            max_loss_4_lots: max_loss_4_lots,
            expected_avg_win: expected_avg_win,
            allowed: false
          }
          return false
        end

        @gate_results[:risk_feasibility] = {
          max_loss_4_lots: max_loss_4_lots,
          expected_avg_win: expected_avg_win,
          allowed: true
        }
        true
      end

      # Helper methods

      def extract_contracts(options)
        if options.is_a?(Hash)
          options["contracts"] || options[:contracts] || []
        elsif options.is_a?(Array)
          options
        else
          []
        end
      end

      def extract_delta_from_options
        return nil unless @options

        contracts = extract_contracts(@options)
        return nil if contracts.empty?

        contract = contracts.first
        (contract["delta"] || contract[:delta] || 0).to_f
      end

      def extract_spot_from_options
        return nil unless @options

        if @options.is_a?(Hash)
          (@options["spot_price"] || @options[:spot_price] || 0).to_f
        else
          nil
        end
      end

      def extract_spot_from_candles
        return nil unless @candles_5m && @candles_5m.any?

        last_candle = @candles_5m.last
        (last_candle["close"] || last_candle[:close] || 0).to_f
      end
    end
  end
end
