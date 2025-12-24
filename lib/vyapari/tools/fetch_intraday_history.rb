# frozen_string_literal: true

require "date"

module Vyapari
  module Tools
    # Tool for fetching intraday price history
    class FetchIntradayHistory < Base
      def self.name = "fetch_intraday_history"

      def self.schema
        {
          type: "function",
          function: {
            name: name,
            description: "STEP 2: Fetches intraday price history (candles) for a symbol. MUST be called after find_instrument. Use security_id, exchange_segment, and instrument (NOT instrument_type) from find_instrument result. Use interval='5' (as a string) for 5-minute candles (valid values: '1', '5', '15', '25', '60'). Returns candle data needed for analyze_trend.",
            parameters: {
              type: "object",
              properties: {
                security_id: {
                  type: "string",
                  description: "Security ID from find_instrument result"
                },
                exchange_segment: {
                  type: "string",
                  description: "Exchange segment from find_instrument result"
                },
                instrument: {
                  type: "string",
                  description: "Instrument field from find_instrument result (NOT instrument_type)"
                },
                interval: {
                  type: "string",
                  description: "Time interval in minutes as a string. Must be one of: '1', '5', '15', '25', '60'. Use '5' for 5-minute candles."
                }
              },
              required: %w[security_id exchange_segment instrument interval]
            }
          }
        }
      end

      def call(p)
        exchange_segment = ExchangeSegmentHelper.normalize(p["exchange_segment"])

        # Convert interval to string (API expects string, not integer)
        interval = p["interval"].to_s
        interval = "5" if interval.empty? || !%w[1 5 15 25 60].include?(interval) # Default to "5" if invalid

        # Fetch raw data from API
        raw_data = DhanHQ::Models::HistoricalData.intraday(
          security_id: p["security_id"],
          exchange_segment: exchange_segment,
          instrument: p["instrument"],
          interval: interval,
          from_date: (Date.today - 7).to_s,
          to_date: Date.today.to_s
        )

        # Transform API response format to candle array format
        # API returns: {"open"=>[val1, val2], "high"=>[val1, val2], ...} or {open: [], close: [], ...}
        # We need: [{"open"=>val1, "high"=>val1, ...}, {"open"=>val2, "high"=>val2, ...}]
        return { candles: [] } if raw_data.nil? || raw_data.empty?

        # Check if data is already in candle array format
        if raw_data.is_a?(Array) && raw_data.first.is_a?(Hash) && (raw_data.first.key?("open") || raw_data.first.key?(:open))
          return { candles: raw_data }
        end

        # Handle both symbol and string keys
        opens = raw_data["open"] || raw_data[:open] || []
        highs = raw_data["high"] || raw_data[:high] || []
        lows = raw_data["low"] || raw_data[:low] || []
        closes = raw_data["close"] || raw_data[:close] || []
        volumes = raw_data["volume"] || raw_data[:volume] || []
        timestamps = raw_data["timestamp"] || raw_data[:timestamp] || []

        # Check if all arrays are empty
        if opens.empty? && highs.empty? && lows.empty? && closes.empty?
          return { candles: [], error: "No historical data available for the specified date range" }
        end

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

        { candles: candles }
      end
    end
  end
end
