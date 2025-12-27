# frozen_string_literal: true

require_relative "../indicators/technical_analysis_adapter"

module Vyapari
  module Options
    # Analyzes volatility expansion for options buying
    # Checks: ATR expansion, session ATR median, ATR slope
    class VolatilityAnalyzer
      def self.analyze(candles_5m, current_time: Time.now)
        new(candles_5m, current_time).analyze
      end

      def initialize(candles_5m, current_time = Time.now)
        @candles_5m = normalize_candles(candles_5m)
        @current_time = current_time
      end

      def analyze
        return { expanding: false, current_atr: 0, median_atr: 0, slope: 0 } if @candles_5m.length < 20

        begin
          # Calculate current ATR
          adapter = Indicators::TechnicalAnalysisAdapter.new(@candles_5m)
          atr_result = adapter.atr(period: 14)

          # Handle case where ATR calculation returns nil or empty
          if atr_result.nil? || atr_result.empty?
            return { expanding: false, current_atr: 0, median_atr: 0, slope: 0,
                     error: "ATR calculation returned no data" }
          end

          current_atr = atr_result&.last&.atr || 0.0
        rescue StandardError => e
          # Handle "Not enough data" and similar errors
          error_msg = e.message.to_s
          if error_msg.include?("Not enough data") || error_msg.include?("insufficient") || error_msg.include?("period")
            return { expanding: false, current_atr: 0, median_atr: 0, slope: 0,
                     error: "Insufficient data for ATR calculation: #{error_msg}" }
          end

          raise # Re-raise if it's a different error
        end

        return { expanding: false, current_atr: current_atr, median_atr: 0, slope: 0 } if current_atr.zero?

        # Calculate session ATR median (from 9:15 to current time)
        session_candles = get_session_candles
        median_atr = calculate_session_atr_median(session_candles)

        # Calculate ATR slope (rate of change)
        slope = calculate_atr_slope

        # ATR is expanding if: current >= median AND slope > 0
        expanding = current_atr >= median_atr && slope > 0

        {
          expanding: expanding,
          current_atr: current_atr.round(2),
          median_atr: median_atr.round(2),
          slope: slope.round(4),
          expansion_ratio: median_atr > 0 ? (current_atr / median_atr).round(2) : 0
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
            volume: (c["volume"] || c[:volume] || 0).to_f,
            timestamp: c["timestamp"] || c[:timestamp]
          }
        end
      end

      def get_session_candles
        # Filter candles from 9:15 AM IST to current time
        # Assuming candles are in chronological order
        @candles_5m.select do |candle|
          timestamp = candle[:timestamp]
          next false unless timestamp

          # Parse timestamp (assuming ISO format or Unix timestamp)
          candle_time = parse_timestamp(timestamp)
          next false unless candle_time

          # Session starts at 9:15 AM IST
          session_start = Time.new(candle_time.year, candle_time.month, candle_time.day, 9, 15, 0, "+05:30")
          candle_time >= session_start && candle_time <= @current_time
        end
      end

      def parse_timestamp(timestamp)
        case timestamp
        when String
          begin
            Time.parse(timestamp)
          rescue StandardError
            nil
          end
        when Numeric
          Time.at(timestamp)
        when Time
          timestamp
        else
          nil
        end
      rescue StandardError
        nil
      end

      def calculate_session_atr_median(session_candles)
        return 0.0 if session_candles.length < 14

        # Calculate ATR for each window of 14 candles
        atr_values = []

        (14..session_candles.length).each do |i|
          window = session_candles[(i - 14)...i]
          adapter = Indicators::TechnicalAnalysisAdapter.new(window)
          atr_result = adapter.atr(period: 14)
          atr_value = atr_result&.last&.atr || 0.0
          atr_values << atr_value if atr_value > 0
        end

        return 0.0 if atr_values.empty?

        # Calculate median
        sorted = atr_values.sort
        mid = sorted.length / 2

        if sorted.length.odd?
          sorted[mid]
        else
          (sorted[mid - 1] + sorted[mid]) / 2.0
        end
      end

      def calculate_atr_slope
        return 0.0 if @candles_5m.length < 28

        # Calculate ATR for two windows: earlier and later
        mid_point = @candles_5m.length / 2

        earlier_window = @candles_5m.first(mid_point)
        later_window = @candles_5m.last(mid_point)

        return 0.0 if earlier_window.length < 14 || later_window.length < 14

        earlier_adapter = Indicators::TechnicalAnalysisAdapter.new(earlier_window)
        later_adapter = Indicators::TechnicalAnalysisAdapter.new(later_window)

        earlier_atr = earlier_adapter.atr(period: 14)&.last&.atr || 0.0
        later_atr = later_adapter.atr(period: 14)&.last&.atr || 0.0

        return 0.0 if earlier_atr.zero?

        # Slope as percentage change
        ((later_atr - earlier_atr) / earlier_atr) * 100
      end
    end
  end
end
