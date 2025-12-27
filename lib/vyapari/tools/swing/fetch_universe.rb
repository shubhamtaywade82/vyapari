# frozen_string_literal: true

require "csv"
require "net/http"
require "uri"
require "json"
require "set"

module Vyapari
  module Tools
    module Swing
      # Tool for fetching swing trading universe from NSE index CSVs
      class FetchUniverse < Base
        # NSE Index CSV URLs - curated for swing trading
        # Focus: Quality stocks with good liquidity
        NSE_INDEX_URLS = {
          "nifty50" => "https://www.niftyindices.com/IndexConstituent/ind_nifty50list.csv",
          "nifty_next50" => "https://www.niftyindices.com/IndexConstituent/ind_niftynext50list.csv",
          "nifty100" => "https://www.niftyindices.com/IndexConstituent/ind_nifty100list.csv",
          "nifty200" => "https://www.niftyindices.com/IndexConstituent/ind_nifty200list.csv",
          "nifty_midcap150" => "https://www.niftyindices.com/IndexConstituent/ind_niftymidcap150list.csv",
          "nifty_midcap100" => "https://www.niftyindices.com/IndexConstituent/ind_niftymidcap100list.csv",
          "nifty_smallcap250" => "https://www.niftyindices.com/IndexConstituent/ind_niftysmallcap250list.csv",
          "nifty_bank" => "https://www.niftyindices.com/IndexConstituent/ind_niftybanklist.csv",
          "nifty_it" => "https://www.niftyindices.com/IndexConstituent/ind_niftyitlist.csv",
          "nifty_pharma" => "https://www.niftyindices.com/IndexConstituent/ind_niftypharmalist.csv"
        }.freeze

        def self.name = "fetch_universe"

        def self.schema
          {
            type: "function",
            function: {
              name: name,
              description: "Fetches the swing trading universe (list of stock symbols) from NSE index constituents. Returns an array of unique stock symbols suitable for swing trading analysis.",
              parameters: {
                type: "object",
                properties: {
                  index_filter: {
                    type: "string",
                    description: "Optional: Filter by specific index (nifty50, nifty100, nifty200, etc.). If not provided, returns combined universe from all indices.",
                    enum: NSE_INDEX_URLS.keys.to_a
                  }
                },
                required: []
              }
            }
          }
        end

        def call(params)
          index_filter = params["index_filter"] || params[:index_filter]

          if index_filter && NSE_INDEX_URLS.key?(index_filter)
            # Fetch single index
            symbols = fetch_index_symbols(index_filter)
            {
              "universe" => symbols,
              "source" => index_filter,
              "count" => symbols.size
            }
          else
            # Fetch combined universe from all indices
            symbols = fetch_combined_universe
            {
              "universe" => symbols,
              "source" => "combined",
              "count" => symbols.size
            }
          end
        rescue StandardError => e
          {
            "error" => e.message,
            "universe" => [],
            "count" => 0
          }
        end

        private

        def fetch_combined_universe
          all_symbols = Set.new

          NSE_INDEX_URLS.each do |index_name, _url|
            begin
              symbols = fetch_index_symbols(index_name)
              all_symbols.merge(symbols)
            rescue StandardError => e
              # Log error but continue with other indices
              warn "Failed to fetch #{index_name}: #{e.message}" if defined?(warn)
            end
          end

          all_symbols.to_a.sort
        end

        def fetch_index_symbols(index_name)
          url = NSE_INDEX_URLS[index_name]
          raise "Unknown index: #{index_name}" unless url

          csv_content = download_csv(url)

          # Validate CSV content
          if csv_content.nil? || csv_content.empty?
            raise "Downloaded CSV content is empty for #{index_name}"
          end

          if csv_content.lines.count < 2
            raise "Downloaded CSV has insufficient data for #{index_name}"
          end

          parse_symbols_from_csv(csv_content)
        end

        def download_csv(url, max_retries: 2)
          uri = URI(url)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.read_timeout = 60
          http.open_timeout = 30

          request = Net::HTTP::Get.new(uri)
          request["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"

          retries = 0
          begin
            response = http.request(request)
            raise "HTTP #{response.code}" unless response.code == "200"

            response.body
          rescue StandardError => e
            retries += 1
            raise e unless retries <= max_retries

            sleep(2 * retries) # Exponential backoff
            retry
          end
        end

        def parse_symbols_from_csv(csv_content)
          symbols = Set.new

          CSV.parse(csv_content, headers: true) do |row|
            # Try multiple column name variations
            symbol = row["Symbol"] || row["SYMBOL"] || row["symbol"] ||
                     row["TradingSymbol"] || row["TRADING_SYMBOL"] ||
                     row["SymbolName"] || row["SYMBOL_NAME"]

            # Skip if symbol is nil or empty (plain Ruby check)
            next if symbol.nil? || symbol.to_s.strip.empty?

            # Clean symbol (remove known suffixes like -EQ, -BE, etc.)
            clean_symbol = symbol.to_s.strip.upcase
            known_suffixes = %w[-EQ -BE -BZ -BL -BT -GC -GD -GO -GP -GS -GT -GU -GV -GW -GX -GY -GZ]
            known_suffixes.each do |suffix|
              clean_symbol = clean_symbol.delete_suffix(suffix) if clean_symbol.end_with?(suffix)
            end

            # Add symbol if not empty (plain Ruby check)
            symbols.add(clean_symbol) unless clean_symbol.empty?
          end

          symbols.to_a.sort
        end
      end
    end
  end
end

