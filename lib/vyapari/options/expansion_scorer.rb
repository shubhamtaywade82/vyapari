# frozen_string_literal: true

module Vyapari
  module Options
    # Expansion scorer: 0-100 score for trade quality
    # Higher score = higher confidence = more aggressive sizing
    class ExpansionScorer
      def self.score(trend:, structure:, volatility:, momentum:, time_window:, strike_quality:)
        new(trend, structure, volatility, momentum, time_window, strike_quality).score
      end

      def initialize(trend, structure, volatility, momentum, time_window, strike_quality)
        @trend = trend.to_s.downcase
        @structure = structure || {}
        @volatility = volatility || {}
        @momentum = momentum || {}
        @time_window = time_window || {}
        @strike_quality = strike_quality || {}
      end

      def score
        total = 0

        # A. Structure Quality (0-30)
        total += score_structure_quality

        # B. Volatility Expansion (0-20)
        total += score_volatility_expansion

        # C. Momentum Quality (0-15)
        total += score_momentum_quality

        # D. Time Advantage (0-10)
        total += score_time_advantage

        # E. Strike Responsiveness (0-10)
        total += score_strike_responsiveness

        # F. Trap/Liquidity Context (0-10)
        total += score_trap_context

        # G. Expected Move Buffer (0-5)
        total += score_expected_move_buffer

        [total, 100].min # Cap at 100
      end

      private

      # A. Structure Quality (0-30)
      def score_structure_quality
        signal = @structure[:signal]

        case signal
        when :bos_with_displacement
          30
        when :trap_failure_retest
          25
        when :range_break_follow_through
          20
        else
          # Use quality from structure analyzer if available
          (@structure[:quality] || 0)
        end
      end

      # B. Volatility Expansion (0-20)
      def score_volatility_expansion
        return 0 unless @volatility[:expanding]

        expansion_ratio = @volatility[:expansion_ratio] || 1.0
        slope = @volatility[:slope] || 0.0

        score = 0

        # Expansion ratio scoring
        if expansion_ratio > 1.5
          score += 12
        elsif expansion_ratio > 1.3
          score += 8
        elsif expansion_ratio > 1.1
          score += 5
        end

        # Slope scoring
        if slope > 5.0
          score += 8
        elsif slope > 2.0
          score += 5
        elsif slope > 0
          score += 2
        end

        [score, 20].min
      end

      # C. Momentum Quality (0-15)
      def score_momentum_quality
        body_percent = @momentum[:body_percent] || 0
        follow_through = @momentum[:follow_through] || false

        score = 0

        # Body % scoring
        if body_percent > 70
          score += 12
        elsif body_percent > 60
          score += 9
        elsif body_percent > 50
          score += 6
        elsif body_percent > 40
          score += 3
        end

        # Follow-through bonus
        score += 3 if follow_through

        [score, 15].min
      end

      # D. Time Advantage (0-10)
      def score_time_advantage
        return 0 unless @time_window[:allowed]

        current_time = @time_window[:current_time] || ""
        hour, minute = current_time.split(":").map(&:to_i)
        time_minutes = (hour * 60) + minute

        # Window 1: 10:30-12:00 (best)
        if time_minutes >= 630 && time_minutes <= 720
          10
        # Window 1: 12:00-13:00 (good)
        elsif time_minutes > 720 && time_minutes <= 780
          8
        # Window 2: 13:45-14:30 (acceptable)
        elsif time_minutes >= 825 && time_minutes <= 870
          6
        else
          0
        end
      end

      # E. Strike Responsiveness (0-10)
      def score_strike_responsiveness
        delta = @strike_quality[:delta] || 0
        spread_pct = @strike_quality[:spread_pct] || 100

        score = 0

        # Delta scoring (optimal range: 0.45-0.50)
        if delta >= 0.45 && delta <= 0.50
          score += 7
        elsif delta >= 0.40 && delta <= 0.55
          score += 5
        elsif delta >= 0.35 && delta <= 0.60
          score += 3
        end

        # Spread scoring
        if spread_pct < 0.5
          score += 3
        elsif spread_pct < 1.0
          score += 2
        end

        [score, 10].min
      end

      # F. Trap/Liquidity Context (0-10)
      def score_trap_context
        signal = @structure[:signal]

        case signal
        when :trap_failure_retest
          10
        when :bos_with_displacement
          # Check if it's a clean break
          (@structure[:body_percent] || 0) > 60 ? 8 : 5
        when :range_break_follow_through
          6
        else
          5 # Neutral
        end
      end

      # G. Expected Move Buffer (0-5)
      def score_expected_move_buffer
        expected_premium = @momentum[:expected_premium] || 0

        if expected_premium >= 15
          5
        elsif expected_premium >= 12
          3
        else
          0
        end
      end
    end
  end
end

