# frozen_string_literal: true

# Risk Calculation Module for Agent B
# Converts Agent A's logical SL/TP to numeric values
# Calculates lot size based on risk limits

module Vyapari
  module Options
    class RiskCalculator
      # Exchange lot sizes (hard-coded constants)
      LOT_SIZES = {
        "NIFTY" => 75,
        "SENSEX" => 20,
        "BANKNIFTY" => 15,
        "FINNIFTY" => 50
      }.freeze

      # Maximum SL percentages (hard caps for options buying)
      MAX_SL_PERCENTAGES = {
        "NIFTY" => 0.30,  # 30% max SL
        "SENSEX" => 0.25, # 25% max SL
        "BANKNIFTY" => 0.30,
        "FINNIFTY" => 0.30
      }.freeze

      # Maximum lots per trade (regardless of capital)
      MAX_LOTS_PER_TRADE = 6

      # Minimum risk-reward ratio
      MIN_RISK_REWARD = 1.5

      def initialize(account_balance:, max_risk_percent: 1.0, instrument: "NIFTY")
        @account_balance = account_balance.to_f
        @max_risk_percent = max_risk_percent.to_f / 100.0
        @instrument = instrument.to_s.upcase
        @lot_size = LOT_SIZES[@instrument] || 75
        @max_sl_percent = MAX_SL_PERCENTAGES[@instrument] || 0.30
      end

      # Calculate maximum risk per trade in rupees
      # @return [Float] Maximum risk amount
      def max_risk_per_trade
        (@account_balance * @max_risk_percent).to_f
      end

      # Calculate lot size based on risk
      # @param entry_price [Float] Entry price per option
      # @param stop_loss_price [Float] Stop-loss price per option
      # @return [Hash] { lots: Integer, risk_per_lot: Float, total_risk: Float, status: Symbol }
      def calculate_lot_size(entry_price:, stop_loss_price:)
        # Calculate risk per lot
        risk_per_lot = (entry_price - stop_loss_price).abs * @lot_size

        # Guard: Risk per lot must be positive
        if risk_per_lot <= 0
          return {
            lots: 0,
            risk_per_lot: 0,
            total_risk: 0,
            status: :rejected,
            reason: "Invalid SL: stop_loss_price (#{stop_loss_price}) must be less than entry_price (#{entry_price})"
          }
        end

        # Calculate allowed lots
        max_risk = (@account_balance * @max_risk_percent).to_f
        allowed_lots = max_risk > 0 && risk_per_lot > 0 ? (max_risk / risk_per_lot).floor : 0

        # Guard: Must have at least 1 lot
        if allowed_lots < 1
          return {
            lots: 0,
            risk_per_lot: risk_per_lot,
            total_risk: risk_per_lot,
            status: :rejected,
            reason: "Risk per lot (#{risk_per_lot.round(2)}) exceeds max risk per trade (#{max_risk.round(2)})"
          }
        end

        # Cap at maximum lots
        final_lots = [allowed_lots, MAX_LOTS_PER_TRADE].min

        # Calculate total risk
        total_risk = final_lots * risk_per_lot

        {
          lots: final_lots,
          risk_per_lot: risk_per_lot,
          total_risk: total_risk,
          status: :approved,
          reason: "Calculated #{final_lots} lot(s) with risk ₹#{total_risk.round(2)} per trade"
        }
      end

      # Convert logical SL to numeric SL price
      # @param sl_logic [String] Structural stop-loss logic from Agent A
      # @param option_ltp [Float] Current option LTP
      # @param underlying_spot [Float] Current underlying spot price
      # @param recent_swing_low [Float, nil] Recent swing low (if available)
      # @return [Hash] { sl_price: Float, sl_percent: Float, status: Symbol, reason: String }
      def convert_sl_logic_to_price(sl_logic:, option_ltp:, underlying_spot: nil, recent_swing_low: nil)
        # Default: Use fixed percentage if logic is unclear
        default_sl_percent = 0.20 # 20% default

        # Try to extract numeric SL from logic or use defaults
        sl_price = case sl_logic.to_s.downcase
                   when /(\d+(?:\.\d+)?)\s*%/
                     # Extract percentage from logic
                     percent = Regexp.last_match(1).to_f / 100.0
                     option_ltp * (1 - percent)
                   when /below\s+(\d+(?:\.\d+)?)/
                     # Extract price level from logic
                     Regexp.last_match(1).to_f
                   when /swing\s+low/i
                     # Use recent swing low if available
                     recent_swing_low || (option_ltp * (1 - default_sl_percent))
                   else
                     # Default: 20% SL
                     option_ltp * (1 - default_sl_percent)
                   end

        # Ensure SL is below entry (for long positions)
        sl_price = [sl_price, option_ltp * 0.70].min # Cap at 30% SL

        # Calculate SL percentage
        sl_percent = ((option_ltp - sl_price) / option_ltp).abs

        # Validate against max SL cap
        if sl_percent > @max_sl_percent
          return {
            sl_price: sl_price,
            sl_percent: sl_percent,
            status: :rejected,
            reason: "SL percentage (#{(sl_percent * 100).round(2)}%) exceeds maximum allowed (#{(@max_sl_percent * 100).round(2)}%)"
          }
        end

        {
          sl_price: sl_price.round(2),
          sl_percent: sl_percent,
          status: :approved,
          reason: "Converted SL logic to price: ₹#{sl_price.round(2)} (#{(sl_percent * 100).round(2)}% SL)"
        }
      end

      # Convert logical TP to numeric TP prices (with partial booking)
      # @param tp_logic [String] Market-based take profit logic from Agent A
      # @param entry_price [Float] Entry price
      # @param stop_loss_price [Float] Stop-loss price
      # @param underlying_spot [Float] Current underlying spot
      # @param previous_day_high [Float, nil] Previous day high (if available)
      # @return [Hash] { partial: Hash, final: Hash, status: Symbol, reason: String }
      def convert_tp_logic_to_prices(tp_logic:, entry_price:, stop_loss_price:, underlying_spot: nil, previous_day_high: nil)
        # Calculate risk
        risk = (entry_price - stop_loss_price).abs

        # Calculate minimum targets (1.5x risk)
        min_partial_rr = 1.2
        min_final_rr = 2.0

        # Try to extract numeric TP from logic or use risk-reward
        partial_price = case tp_logic.to_s.downcase
                       when /(\d+(?:\.\d+)?)\s*%/
                         # Extract percentage from logic
                         percent = Regexp.last_match(1).to_f / 100.0
                         entry_price * (1 + percent)
                       when /above\s+(\d+(?:\.\d+)?)/
                         # Extract price level from logic
                         Regexp.last_match(1).to_f
                       when /previous\s+day\s+high/i
                         # Use previous day high if available
                         previous_day_high || (entry_price + (risk * min_partial_rr))
                       else
                         # Default: Use risk-reward
                         entry_price + (risk * min_partial_rr)
                       end

        final_price = entry_price + (risk * min_final_rr)

        # Ensure partial < final
        partial_price = [partial_price, final_price * 0.7].min

        # Calculate RR ratios
        partial_rr = (partial_price - entry_price) / risk
        final_rr = (final_price - entry_price) / risk

        # Validate minimum RR
        if partial_rr < min_partial_rr || final_rr < min_final_rr
          return {
            partial: { price: partial_price, rr: partial_rr, exit_pct: 50 },
            final: { price: final_price, rr: final_rr, exit_pct: 50 },
            status: :rejected,
            reason: "TP does not meet minimum RR requirement (partial: #{partial_rr.round(2)}x, final: #{final_rr.round(2)}x)"
          }
        end

        {
          partial: {
            price: partial_price.round(2),
            rr: partial_rr.round(2),
            exit_pct: 50
          },
          final: {
            price: final_price.round(2),
            rr: final_rr.round(2),
            exit_pct: 50
          },
          status: :approved,
          reason: "Converted TP logic to prices: Partial ₹#{partial_price.round(2)} (#{partial_rr.round(2)}x RR), Final ₹#{final_price.round(2)} (#{final_rr.round(2)}x RR)"
        }
      end

      # Validate complete trade plan
      # @param trade_plan [Hash] Trade plan from Agent A
      # @param option_ltp [Float] Current option LTP
      # @param funds_available [Float] Available funds
      # @return [Hash] Validation result
      def validate_trade_plan(trade_plan:, option_ltp:, funds_available:)
        # Step 1: Convert SL logic to price
        sl_result = convert_sl_logic_to_price(
          sl_logic: trade_plan[:stop_loss_logic] || trade_plan["stop_loss_logic"],
          option_ltp: option_ltp
        )

        return { status: :rejected, reason: sl_result[:reason] } if sl_result[:status] == :rejected

        # Step 2: Convert TP logic to prices
        tp_result = convert_tp_logic_to_prices(
          tp_logic: trade_plan[:take_profit_logic] || trade_plan["take_profit_logic"],
          entry_price: option_ltp,
          stop_loss_price: sl_result[:sl_price]
        )

        return { status: :rejected, reason: tp_result[:reason] } if tp_result[:status] == :rejected

        # Step 3: Calculate lot size
        lot_result = calculate_lot_size(
          entry_price: option_ltp,
          stop_loss_price: sl_result[:sl_price]
        )

        return { status: :rejected, reason: lot_result[:reason] } if lot_result[:status] == :rejected

        # Step 4: Check funds
        required_margin = option_ltp * @lot_size * lot_result[:lots]
        if required_margin > funds_available
          return {
            status: :rejected,
            reason: "Insufficient funds: Required ₹#{required_margin.round(2)}, Available ₹#{funds_available.round(2)}"
          }
        end

        # All validations passed
        {
          status: :approved,
          sl_price: sl_result[:sl_price],
          sl_percent: sl_result[:sl_percent],
          tp_partial: tp_result[:partial],
          tp_final: tp_result[:final],
          lots: lot_result[:lots],
          quantity: lot_result[:lots] * @lot_size,
          total_risk: lot_result[:total_risk],
          required_margin: required_margin,
          reason: "Trade plan validated successfully"
        }
      end

      attr_reader :lot_size, :max_sl_percent, :max_risk_per_trade
    end
  end
end

