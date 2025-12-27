# frozen_string_literal: true

require_relative "daily_loss_tracker"

module Vyapari
  module Options
    # Dynamic lot sizing based on expansion score
    class LotSizer
      MAX_LOTS = 4

      def self.size_for(score:, daily_loss_cap_remaining: nil, premium: nil, stop_loss_pct: 0.65)
        new(score, daily_loss_cap_remaining, premium, stop_loss_pct).size_for
      end

      def initialize(score, daily_loss_cap_remaining, premium, stop_loss_pct)
        @score = score.to_i
        @daily_loss_cap_remaining = daily_loss_cap_remaining
        @premium = premium.to_f
        @stop_loss_pct = stop_loss_pct
      end

      def size_for
        # Base lot size from score
        base_lots = calculate_base_lots

        # Apply daily loss cap constraint
        final_lots = apply_loss_cap_constraint(base_lots)

        final_lots
      end

      private

      def calculate_base_lots
        case @score
        when 0...50
          0 # Blocked
        when 50...65
          1 # Small size
        when 65...75
          2 # Standard
        when 75...85
          3 # Aggressive
        when 85..100
          4 # Maximum
        else
          0
        end
      end

      def apply_loss_cap_constraint(base_lots)
        return base_lots if base_lots == 0
        return base_lots unless @daily_loss_cap_remaining
        return base_lots if @premium.zero?

        # Calculate max loss for base lots
        max_loss_per_lot = @premium * @stop_loss_pct
        max_loss_for_lots = max_loss_per_lot * base_lots

        # If max loss exceeds remaining cap, reduce lots
        if max_loss_for_lots > @daily_loss_cap_remaining
          # Calculate how many lots we can afford
          affordable_lots = (@daily_loss_cap_remaining / max_loss_per_lot).floor
          [affordable_lots, 0].max
        else
          base_lots
        end
      end
    end
  end
end

