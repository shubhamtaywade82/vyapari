# frozen_string_literal: true

module Vyapari
  module Options
    # Analyzes momentum for options buying
    # Calculates: expected move, body %, follow-through
    class MomentumAnalyzer
      def self.analyze(candles_5m, spot_price, delta = 0.45)
        new(candles_5m, spot_price, delta).analyze
      end

      def initialize(candles_5m, spot_price, delta = 0.45)
        @candles_5m = normalize_candles(candles_5m)
        @spot_price = spot_price.to_f
        @delta = delta.to_f
      end

      def analyze
        if @candles_5m.length < 10
          return {
            expected_index_move: 0,
            expected_premium: 0,
            body_percent: 0,
            follow_through: false,
            momentum_quality: 0
          }
        end

        # Calculate expected index move
        expected_move = calculate_expected_move

        # Calculate expected premium (index move × delta)
        expected_premium = expected_move * @delta

        # Analyze last candle body %
        last_candle = @candles_5m.last
        body = (last_candle[:close] - last_candle[:open]).abs
        range = last_candle[:high] - last_candle[:low]
        body_percent = range > 0 ? (body / range) * 100 : 0

        # Check for follow-through
        follow_through = check_follow_through

        # Calculate momentum quality score
        momentum_quality = calculate_momentum_quality(body_percent, follow_through)

        {
          expected_index_move: expected_move.round(2),
          expected_premium: expected_premium.round(2),
          body_percent: body_percent.round(2),
          follow_through: follow_through,
          momentum_quality: momentum_quality
        }
      end

      private

      def normalize_candles(candles)
        return [] unless candles.is_a?(Array)

        candles.map do |c|
          {
            open: (c["open"] || c[:open]).to_f,
            high: (c["high"] || c[:high]).to_f,
            low: (c["low"] || c[:low]).to_f,
            close: (c["close"] || c[:close]).to_f,
            volume: (c["volume"] || c[:volume] || 0).to_f
          }
        end
      end

      def calculate_expected_move
        return 0.0 if @candles_5m.length < 5

        # Use recent momentum (last 5-10 candles)
        recent = @candles_5m.last(10)
        return 0.0 if recent.length < 3

        # Calculate average move size
        moves = []

        (1...recent.length).each do |i|
          move = (recent[i][:close] - recent[i - 1][:close]).abs
          moves << move
        end

        return 0.0 if moves.empty?

        # Use average of recent moves, weighted towards most recent
        weighted_moves = []
        moves.each_with_index do |move, idx|
          weight = idx + 1 # More recent = higher weight
          weighted_moves << (move * weight)
        end

        avg_move = weighted_moves.sum / (1..moves.length).sum

        # Factor in volatility (use recent range)
        recent_range = recent.map { |c| c[:high] - c[:low] }.max
        volatility_factor = recent_range > 0 ? (recent_range / @spot_price) : 0.01

        # Expected move = average move × (1 + volatility factor)
        expected = avg_move * (1 + volatility_factor)

        # Cap at reasonable maximum (e.g., 2% of spot)
        max_move = @spot_price * 0.02
        [expected, max_move].min
      end

      def check_follow_through
        return false if @candles_5m.length < 3

        # Check last 2-3 candles for continuation
        last_candles = @candles_5m.last(3)
        return false if last_candles.length < 2

        # Check if candles continue in same direction
        direction = nil

        last_candles.each_cons(2) do |a, b|
          if b[:close] > a[:close]
            current_dir = :up
          elsif b[:close] < a[:close]
            current_dir = :down
          else
            return false # No clear direction
          end

          if direction.nil?
            direction = current_dir
          elsif direction != current_dir
            return false # Direction changed
          end
        end

        true
      end

      def calculate_momentum_quality(body_percent, follow_through)
        score = 0

        # Body % scoring
        if body_percent > 70
          score += 15
        elsif body_percent > 60
          score += 12
        elsif body_percent > 50
          score += 8
        elsif body_percent > 40
          score += 4
        end

        # Follow-through scoring
        score += 5 if follow_through

        score
      end
    end
  end
end
