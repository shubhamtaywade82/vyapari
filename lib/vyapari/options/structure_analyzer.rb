# frozen_string_literal: true

module Vyapari
  module Options
    # Enhanced structure analysis for options buying
    # Detects: BOS with displacement, trap failure retest, range break with follow-through
    class StructureAnalyzer
      def self.analyze(candles_5m, candles_15m = nil)
        new(candles_5m, candles_15m).analyze
      end

      def initialize(candles_5m, candles_15m = nil)
        @candles_5m = normalize_candles(candles_5m)
        @candles_15m = candles_15m ? normalize_candles(candles_15m) : nil
      end

      def analyze
        return { signal: :none, quality: 0 } if @candles_5m.length < 20

        # Check for BOS with displacement (highest priority)
        bos_result = detect_bos_with_displacement
        return bos_result if bos_result[:signal] != :none

        # Check for trap failure retest
        trap_result = detect_trap_failure_retest
        return trap_result if trap_result[:signal] != :none

        # Check for range break with follow-through
        range_result = detect_range_break_follow_through
        return range_result if range_result[:signal] != :none

        { signal: :none, quality: 0 }
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

      def detect_bos_with_displacement
        return { signal: :none, quality: 0 } if @candles_5m.length < 10

        recent = @candles_5m.last(10)

        # Find recent swing high/low
        swing_high = recent.map { |c| c[:high] }.max
        swing_low = recent.map { |c| c[:low] }.min

        # Check last 3-5 candles for break of structure
        last_candles = recent.last(5)
        return { signal: :none, quality: 0 } if last_candles.length < 3

        # Check for break above swing high (bullish BOS)
        last_candle = last_candles.last
        prev_high = recent.first(5).map { |c| c[:high] }.max

        if last_candle[:close] > prev_high
          # Check for displacement (large candle body > 60%)
          body = (last_candle[:close] - last_candle[:open]).abs
          range = last_candle[:high] - last_candle[:low]

          if range > 0 && (body / range) > 0.6
            # Check for follow-through (next 1-2 candles continue)
            follow_through = check_follow_through(recent.last(3), :up)

            if follow_through
              return {
                signal: :bos_with_displacement,
                direction: :bullish,
                quality: 30,
                body_percent: ((body / range) * 100).round(2)
              }
            end
          end
        end

        # Check for break below swing low (bearish BOS)
        prev_low = recent.first(5).map { |c| c[:low] }.min

        if last_candle[:close] < prev_low
          body = (last_candle[:close] - last_candle[:open]).abs
          range = last_candle[:high] - last_candle[:low]

          if range > 0 && (body / range) > 0.6
            follow_through = check_follow_through(recent.last(3), :down)

            if follow_through
              return {
                signal: :bos_with_displacement,
                direction: :bearish,
                quality: 30,
                body_percent: ((body / range) * 100).round(2)
              }
            end
          end
        end

        { signal: :none, quality: 0 }
      end

      def detect_trap_failure_retest
        return { signal: :none, quality: 0 } if @candles_5m.length < 15

        recent = @candles_5m.last(15)

        # Look for pattern: fake break → immediate reversal → reclaim → strong move
        # Simplified: check for reversal after break
        first_half = recent.first(8)
        second_half = recent.last(7)

        return { signal: :none, quality: 0 } if first_half.length < 5 || second_half.length < 3

        # Check for fake breakout (price breaks high, then reverses)
        first_high = first_half.map { |c| c[:high] }.max
        first_low = first_half.map { |c| c[:low] }.min

        # Check if second half shows strong reversal
        second_start = second_half.first[:close]
        second_end = second_half.last[:close]

        # Bullish trap: fake breakdown, then strong up move
        if second_start < first_low && second_end > first_low
          move_strength = (second_end - second_start).abs
          first_range = first_high - first_low

          if move_strength > (first_range * 0.5)
            return {
              signal: :trap_failure_retest,
              direction: :bullish,
              quality: 25
            }
          end
        end

        # Bearish trap: fake breakout, then strong down move
        if second_start > first_high && second_end < first_high
          move_strength = (second_start - second_end).abs
          first_range = first_high - first_low

          if move_strength > (first_range * 0.5)
            return {
              signal: :trap_failure_retest,
              direction: :bearish,
              quality: 25
            }
          end
        end

        { signal: :none, quality: 0 }
      end

      def detect_range_break_follow_through
        return { signal: :none, quality: 0 } if @candles_5m.length < 20

        recent = @candles_5m.last(20)

        # Find range (compression zone)
        first_half = recent.first(10)
        second_half = recent.last(10)

        return { signal: :none, quality: 0 } if first_half.length < 5 || second_half.length < 5

        range_high = first_half.map { |c| c[:high] }.max
        range_low = first_half.map { |c| c[:low] }.min
        range_size = range_high - range_low

        return { signal: :none, quality: 0 } if range_size.zero?

        # Check if second half breaks range
        second_high = second_half.map { |c| c[:high] }.max
        second_low = second_half.map { |c| c[:low] }.min

        # Bullish break
        if second_high > range_high
          # Check for follow-through
          last_candles = second_half.last(3)
          follow_through = last_candles.all? { |c| c[:close] > range_high }

          if follow_through
            # Check for large expansion candle
            expansion_candle = second_half.find { |c| (c[:high] - c[:low]) > (range_size * 1.2) }

            if expansion_candle
              return {
                signal: :range_break_follow_through,
                direction: :bullish,
                quality: 20
              }
            end
          end
        end

        # Bearish break
        if second_low < range_low
          last_candles = second_half.last(3)
          follow_through = last_candles.all? { |c| c[:close] < range_low }

          if follow_through
            expansion_candle = second_half.find { |c| (c[:high] - c[:low]) > (range_size * 1.2) }

            if expansion_candle
              return {
                signal: :range_break_follow_through,
                direction: :bearish,
                quality: 20
              }
            end
          end
        end

        { signal: :none, quality: 0 }
      end

      def check_follow_through(candles, direction)
        return false if candles.length < 2

        if direction == :up
          # Check if candles continue upward
          candles.each_cons(2).all? { |a, b| b[:close] >= a[:close] }
        else
          # Check if candles continue downward
          candles.each_cons(2).all? { |a, b| b[:close] <= a[:close] }
        end
      end
    end
  end
end
