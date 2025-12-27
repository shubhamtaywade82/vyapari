# frozen_string_literal: true

require_relative "../options/pre_trade_gate"
require_relative "../options/expansion_scorer"
require_relative "../options/lot_sizer"

module Vyapari
  module Tools
    # Tool for recommending trades with pre-trade gates and expansion scoring
    class RecommendTrade < Base
      def self.name = "recommend_trade"

      def self.schema
        {
          type: "function",
          function: {
            name: name,
            description: "STEP 6: Final step - Recommends a trade based on market analysis with pre-trade gates and expansion scoring. MUST be called last. ALL parameters (options, trend, candles_5m, candles_15m) are automatically injected from context - call with empty parameters: {}.",
            parameters: {
              type: "object",
              properties: {},
              required: []
            }
          }
        }
      end

      def call(p)
        trend = p["trend"] || p[:trend]
        options = p["options"] || p[:options]
        candles_5m = p["candles_5m"] || p[:candles_5m] || p["candles"] || p[:candles] # Fallback to candles
        candles_15m = p["candles_15m"] || p[:candles_15m]

        # Extract spot price from options or candles
        spot_price = extract_spot_price(options, candles_5m)

        # Run pre-trade gate
        gate_result = Options::PreTradeGate.run(
          trend: trend,
          options: options,
          candles_5m: candles_5m,
          candles_15m: candles_15m,
          current_time: Time.now,
          spot_price: spot_price
        )

        unless gate_result[:allowed]
          return {
            action: "NO_TRADE",
            reason: gate_result[:reason] || "Pre-trade gates failed",
            failed_gates: gate_result[:failed_gates],
            gate_results: gate_result[:gate_results]
          }
        end

        # Calculate expansion score
        score = Options::ExpansionScorer.score(
          trend: trend,
          structure: gate_result[:structure],
          volatility: gate_result[:volatility],
          momentum: gate_result[:momentum],
          time_window: gate_result[:time_window],
          strike_quality: gate_result[:strike_quality]
        )

        # If score too low, block trade
        if score < 50
          return {
            action: "NO_TRADE",
            reason: "Expansion score too low: #{score}/100 (minimum: 50)",
            expansion_score: score,
            gate_results: gate_result[:gate_results]
          }
        end

        # Extract options - can be hash (from fetch_option_chain) or array (from LLM)
        opt = options

        # Handle hash format from fetch_option_chain (has contracts array)
        if opt.is_a?(Hash)
          contracts = opt["contracts"] || opt[:contracts] || []
          raise "No contracts available in options" if contracts.empty?

          # Use first contract for entry
          contract = contracts.first
          premium = (contract["last_price"] || contract[:last_price] ||
                     contract["average_price"] || contract[:average_price] || 0).to_f

          raise "Invalid premium: #{premium}" if premium.zero?

          security_id = contract["security_id"] || contract[:security_id]
          side = (opt["side"] || opt[:side] || "CE").to_s.upcase
        elsif opt.is_a?(Array) && !opt.empty?
          # Handle array format (direct contracts)
          contract = opt.first
          premium = (contract["last_price"] || contract[:last_price] ||
                     contract["average_price"] || contract[:average_price] || 0).to_f

          raise "Invalid premium: #{premium}" if premium.zero?

          security_id = contract["security_id"] || contract[:security_id]
          side = "CE" # Default, should come from context
        else
          raise "Invalid options format: expected hash with contracts or array of contracts"
        end

        # Calculate lot size based on expansion score
        daily_loss_cap_remaining = Options::DailyLossTracker.remaining
        lot_size = Options::LotSizer.size_for(
          score: score,
          daily_loss_cap_remaining: daily_loss_cap_remaining,
          premium: premium,
          stop_loss_pct: 0.65
        )

        # If lot size is 0, block trade
        if lot_size == 0
          return {
            action: "NO_TRADE",
            reason: "Lot size is 0 (score: #{score}, daily loss cap remaining: ₹#{daily_loss_cap_remaining.round(2)})",
            expansion_score: score,
            daily_loss_cap_remaining: daily_loss_cap_remaining
          }
        end

        # Calculate position size (quantity = lot_size × lot multiplier)
        # Assuming 1 lot = 50 shares for NIFTY/BANKNIFTY
        lot_multiplier = 50
        quantity = lot_size * lot_multiplier

        {
          action: "BUY",
          side: side,
          security_id: security_id,
          entry_price: premium,
          stop_loss_price: premium * 0.65,
          target_price: premium * 1.4,
          quantity: quantity,
          lot_size: lot_size,
          expansion_score: score,
          gate_results: gate_result[:gate_results],
          expected_premium: gate_result[:momentum]&.dig(:expected_premium),
          expected_index_move: gate_result[:momentum]&.dig(:expected_index_move)
        }
      end

      private

      def extract_spot_price(options, candles)
        # Try to get from options first
        if options.is_a?(Hash)
          spot = options["spot_price"] || options[:spot_price]
          return spot.to_f if spot
        end

        # Fallback to last candle close
        if candles.is_a?(Array) && candles.any?
          last_candle = candles.last
          return (last_candle["close"] || last_candle[:close]).to_f
        end

        nil
      end
    end
  end
end
