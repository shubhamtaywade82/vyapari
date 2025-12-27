# frozen_string_literal: true

module Vyapari
  module Options
    # Classifies market day type for options buying strategy
    # Valid types: :trend, :trap_resolution, :range_expansion
    # Invalid types: :inside_day, :narrow_range, :choppy
    class DayTypeClassifier
      def self.classify(candles_15m, candles_5m = nil)
        new(candles_15m, candles_5m).classify
      end

      def initialize(candles_15m, candles_5m = nil)
        @candles_15m = normalize_candles(candles_15m)
        @candles_5m = candles_5m ? normalize_candles(candles_5m) : nil
      end

      def classify
        return :unknown if @candles_15m.length < 20

        # Check for invalid day types first
        return :inside_day if inside_day?
        return :narrow_range if narrow_range?
        return :choppy if choppy?

        # Check for valid day types
        return :trend if trend_day?
        return :trap_resolution if trap_resolution?
        return :range_expansion if range_expansion?

        :unknown
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
            volume: (c["volume"] || c[:volume] || 0).to_f,
            timestamp: c["timestamp"] || c[:timestamp]
          }
        end
      end

      def inside_day?
        return false if @candles_15m.length < 2

        # Inside day: today's high < yesterday's high AND today's low > yesterday's low
        recent = @candles_15m.last(2)
        return false if recent.length < 2

        today = recent.last
        yesterday = recent.first

        today[:high] < yesterday[:high] && today[:low] > yesterday[:low]
      end

      def narrow_range?
        return false if @candles_15m.length < 10

        # Calculate ATR for range comparison
        atr = calculate_atr(@candles_15m.last(20), period: 14)
        return false if atr.zero?

        # Get recent candles (last 5)
        recent = @candles_15m.last(5)
        return false if recent.empty?

        # Calculate average range of recent candles
        avg_range = recent.map { |c| c[:high] - c[:low] }.sum / recent.length

        # Narrow range: average range < 50% of ATR
        avg_range < (atr * 0.5)
      end

      def choppy?
        return false if @candles_15m.length < 10

        # Choppy: many overlapping candles, no clear direction
        recent = @candles_15m.last(10)
        overlapping_count = 0

        (1...recent.length).each do |i|
          prev = recent[i - 1]
          curr = recent[i]

          # Check if candles overlap significantly (>50%)
          overlap = [curr[:high], prev[:high]].min - [curr[:low], prev[:low]].max
          candle_range = [curr[:high] - curr[:low], prev[:high] - prev[:low]].max

          overlapping_count += 1 if overlap > (candle_range * 0.5)
        end

        # Choppy if >70% of candles overlap
        overlapping_count > (recent.length * 0.7)
      end

      def trend_day?
        return false if @candles_15m.length < 20

        # Trend day: clear HH/HL or LL/LH structure with higher TF alignment
        recent = @candles_15m.last(20)

        # Detect swing highs and lows
        highs = []
        lows = []

        (1...(recent.length - 1)).each do |i|
          prev = recent[i - 1]
          curr = recent[i]
          nxt = recent[i + 1]

          if curr[:high] > prev[:high] && curr[:high] > nxt[:high]
            highs << { index: i, price: curr[:high] }
          end

          if curr[:low] < prev[:low] && curr[:low] < nxt[:low]
            lows << { index: i, price: curr[:low] }
          end
        end

        return false if highs.length < 2 || lows.length < 2

        # Check for HH/HL (bullish trend)
        last_two_highs = highs.last(2)
        last_two_lows = lows.last(2)

        bullish_trend = last_two_highs.length == 2 && last_two_highs[1][:price] > last_two_highs[0][:price] &&
                        last_two_lows.length == 2 && last_two_lows[1][:price] > last_two_lows[0][:price]

        # Check for LL/LH (bearish trend)
        bearish_trend = last_two_highs.length == 2 && last_two_highs[1][:price] < last_two_highs[0][:price] &&
                         last_two_lows.length == 2 && last_two_lows[1][:price] < last_two_lows[0][:price]

        bullish_trend || bearish_trend
      end

      def trap_resolution?
        return false if @candles_15m.length < 10

        # Trap resolution: fake breakout/breakdown followed by reclaim and displacement
        recent = @candles_15m.last(10)
        return false if recent.length < 6

        # Look for pattern: break structure → reverse → reclaim → strong move
        # Simplified: check for reversal after initial move
        first_half = recent.first(recent.length / 2)
        second_half = recent.last(recent.length / 2)

        # Check if first half shows one direction, second half reverses strongly
        first_direction = first_half.last[:close] > first_half.first[:close] ? :up : :down
        second_direction = second_half.last[:close] > second_half.first[:close] ? :up : :down

        # Trap if directions are opposite and second move is strong
        if first_direction != second_direction
          first_move = (first_half.last[:close] - first_half.first[:close]).abs
          second_move = (second_half.last[:close] - second_half.first[:close]).abs

          # Second move should be at least 1.5x first move (displacement)
          return second_move > (first_move * 1.5)
        end

        false
      end

      def range_expansion?
        return false if @candles_15m.length < 20

        # Range expansion: compression (low ATR) followed by sudden large candle
        # Calculate ATR for first half and second half
        first_half = @candles_15m.first(@candles_15m.length / 2)
        second_half = @candles_15m.last(@candles_15m.length / 2)

        return false if first_half.length < 10 || second_half.length < 10

        atr_first = calculate_atr(first_half, period: 10)
        atr_second = calculate_atr(second_half, period: 10)

        return false if atr_first.zero?

        # Check if second half ATR is significantly higher (expansion)
        atr_expansion = atr_second > (atr_first * 1.3)

        # Check for large range candle in second half
        large_candle = second_half.any? do |c|
          range = c[:high] - c[:low]
          range > (atr_first * 1.5)
        end

        atr_expansion && large_candle
      end

      def calculate_atr(candles, period: 14)
        return 0.0 if candles.length < period + 1

        true_ranges = []

        (1...candles.length).each do |i|
          high = candles[i][:high]
          low = candles[i][:low]
          prev_close = candles[i - 1][:close]

          tr1 = high - low
          tr2 = (high - prev_close).abs
          tr3 = (low - prev_close).abs

          true_ranges << [tr1, tr2, tr3].max
        end

        return 0.0 if true_ranges.empty?

        # Calculate ATR as average of true ranges
        atr = true_ranges.last(period).sum.to_f / period
        atr.round(2)
      end
    end
  end
end

