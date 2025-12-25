# frozen_string_literal: true

require "date"
require_relative "../exchange_segment_helper"

module Vyapari
  module Tools
    module Swing
      # Tool for fetching swing trading historical data (1H and 1D timeframes)
      class FetchSwingHistory < Base
        def self.name = "fetch_swing_history"

        def self.schema
          {
            type: "function",
            function: {
              name: name,
              description: "Fetches swing trading historical data (1H hourly and 1D daily candles) for a stock symbol. Required for swing trading analysis.",
              parameters: {
                type: "object",
                properties: {
                  symbol: {
                    type: "string",
                    description: "Stock symbol (e.g., 'RELIANCE', 'HDFCBANK'). Must be from NSE_EQ exchange."
                  }
                },
                required: ["symbol"]
              }
            }
          }
        end

        def call(params)
          symbol = params["symbol"] || params[:symbol]
          raise "Symbol parameter is required" if symbol.nil? || symbol.to_s.strip.empty?

          symbol = symbol.to_s.upcase.strip
          exchange_segment = "NSE_EQ" # Swing trading uses equity stocks

          # Find instrument
          inst = DhanHQ::Models::Instrument.find(exchange_segment, symbol)
          raise "Instrument not found for symbol: #{symbol}" unless inst

          # Fetch 1H data (last 30 days)
          hourly_data = fetch_hourly_data(inst, 30)

          # Fetch 1D data (last 60 days)
          daily_data = fetch_daily_data(inst, 60)

          {
            "symbol" => symbol,
            "exchange_segment" => exchange_segment,
            "security_id" => inst.security_id.to_s,
            "1h" => hourly_data,
            "1d" => daily_data,
            "1h_count" => hourly_data.size,
            "1d_count" => daily_data.size
          }
        rescue StandardError => e
          {
            "error" => e.message,
            "symbol" => symbol,
            "1h" => [],
            "1d" => [],
            "1h_count" => 0,
            "1d_count" => 0
          }
        end

        private

        def fetch_hourly_data(instrument, days)
          begin
            raw_data = DhanHQ::Models::HistoricalData.intraday(
              security_id: instrument.security_id,
              exchange_segment: instrument.exchange_segment,
              instrument: instrument.instrument || instrument.instrument_type,
              interval: "60", # 1 hour
              from_date: (Date.today - days).to_s,
              to_date: Date.today.to_s
            )

            transform_to_candles(raw_data)
          rescue StandardError => e
            warn "Failed to fetch hourly data for #{instrument.instrument}: #{e.message}" if defined?(warn)
            []
          end
        end

        def fetch_daily_data(instrument, days)
          begin
            # Try HistoricalData.daily if available
            if DhanHQ::Models::HistoricalData.respond_to?(:daily)
              raw_data = DhanHQ::Models::HistoricalData.daily(
                security_id: instrument.security_id,
                exchange_segment: instrument.exchange_segment,
                instrument: instrument.instrument || instrument.instrument_type,
                from_date: (Date.today - days).to_s,
                to_date: Date.today.to_s
              )
              return transform_to_candles(raw_data)
            end

            # Fallback: Use instrument.daily method if available
            if instrument.respond_to?(:daily)
              raw_data = instrument.daily(
                from_date: (Date.today - days).to_s,
                to_date: Date.today.to_s
              )
              return transform_to_candles(raw_data)
            end

            # Last resort: Return empty array with warning
            warn "Daily data method not available for #{instrument.instrument}" if defined?(warn)
            []
          rescue StandardError => e
            warn "Failed to fetch daily data for #{instrument.instrument}: #{e.message}" if defined?(warn)
            []
          end
        end

        def transform_to_candles(raw_data)
          return [] if raw_data.nil? || raw_data.empty?

          # Check if data is already in candle array format
          if raw_data.is_a?(Array) && raw_data.first.is_a?(Hash) && (raw_data.first.key?("open") || raw_data.first.key?(:open))
            return raw_data
          end

          # Handle both symbol and string keys
          opens = raw_data["open"] || raw_data[:open] || []
          highs = raw_data["high"] || raw_data[:high] || []
          lows = raw_data["low"] || raw_data[:low] || []
          closes = raw_data["close"] || raw_data[:close] || []
          volumes = raw_data["volume"] || raw_data[:volume] || []
          timestamps = raw_data["timestamp"] || raw_data[:timestamp] || []

          # Check if all arrays are empty
          return [] if opens.empty? && highs.empty? && lows.empty? && closes.empty?

          # Determine the length based on the longest array
          max_length = [opens.length, highs.length, lows.length, closes.length].max

          candles = (0...max_length).map do |i|
            {
              "open" => opens[i]&.to_f,
              "high" => highs[i]&.to_f,
              "low" => lows[i]&.to_f,
              "close" => closes[i]&.to_f,
              "volume" => volumes[i]&.to_f,
              "timestamp" => timestamps[i]&.to_f
            }
          end.compact

          candles
        end
      end
    end
  end
end

