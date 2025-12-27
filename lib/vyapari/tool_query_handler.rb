# frozen_string_literal: true

require "date"

# Simple tool query handler for direct data API calls
# Allows testing individual tools without going through full trading workflow
module Vyapari
  class ToolQueryHandler
    # Map query patterns to tool names and argument extractors
    TOOL_PATTERNS = {
      /get\s+(\w+)\s+ltp/i => {
        tool: "dhan.market.ltp",
        extract_args: lambda { |match, query|
          symbol = match[1]
          { symbol: symbol, exchange_segment: symbol.match?(/NIFTY|BANKNIFTY|SENSEX/i) ? "IDX_I" : "NSE_EQ" }
        }
      },
      /fetch\s+(\w+)\s+ltp/i => {
        tool: "dhan.market.ltp",
        extract_args: lambda { |match, query|
          symbol = match[1]
          { symbol: symbol, exchange_segment: symbol.match?(/NIFTY|BANKNIFTY|SENSEX/i) ? "IDX_I" : "NSE_EQ" }
        }
      },
      /(\w+)\s+ltp/i => {
        tool: "dhan.market.ltp",
        extract_args: lambda { |match, query|
          symbol = match[1]
          { symbol: symbol, exchange_segment: symbol.match?(/NIFTY|BANKNIFTY|SENSEX/i) ? "IDX_I" : "NSE_EQ" }
        }
      },
      /get\s+(\w+)\s+quote/i => {
        tool: "dhan.market.quote",
        extract_args: lambda { |match, query|
          symbol = match[1]
          { symbol: symbol, exchange_segment: symbol.match?(/NIFTY|BANKNIFTY|SENSEX/i) ? "IDX_I" : "NSE_EQ" }
        }
      },
      /find\s+instrument\s+(\w+)/i => {
        tool: "dhan.instrument.find",
        extract_args: lambda { |match, query|
          symbol = match[1]
          { symbol: symbol, exchange_segment: symbol.match?(/NIFTY|BANKNIFTY|SENSEX/i) ? "IDX_I" : "NSE_EQ" }
        }
      },
      /get\s+(\w+)\s+option\s+chain/i => {
        tool: "dhan.option.chain",
        extract_args: lambda { |match, query|
          underlying = match[1]
          # Try to extract expiry from query, otherwise will be auto-resolved from expiry list
          expiry_match = query.match(/(\d{4}-\d{2}-\d{2})|expiry[:\s]+(\d{4}-\d{2}-\d{2})/i)
          expiry = expiry_match ? (expiry_match[1] || expiry_match[2]) : nil # Will be resolved to nearest expiry

          {
            underlying_scrip: underlying, # Will be resolved to security_id integer
            underlying_seg: "IDX_I",
            expiry: expiry, # nil if not specified - will be auto-resolved
            symbol: underlying # Keep symbol for resolution
          }
        }
      },
      /(\w+)\s+option\s+chain/i => {
        tool: "dhan.option.chain",
        extract_args: lambda { |match, query|
          underlying = match[1]
          expiry_match = query.match(/(\d{4}-\d{2}-\d{2})|expiry[:\s]+(\d{4}-\d{2}-\d{2})/i)
          expiry = expiry_match ? (expiry_match[1] || expiry_match[2]) : nil # Will be resolved to nearest expiry

          {
            underlying_scrip: underlying, # Will be resolved to security_id integer
            underlying_seg: "IDX_I",
            expiry: expiry,
            symbol: underlying # Keep symbol for resolution
          }
        }
      },
      /get\s+funds|balance|margin/i => {
        tool: "dhan.funds.balance",
        extract_args: ->(match, query) { {} }
      },
      /get\s+positions/i => {
        tool: "dhan.positions.list",
        extract_args: ->(match, query) { {} }
      },
      /get\s+orders/i => {
        tool: "dhan.orders.list",
        extract_args: ->(match, query) { {} }
      }
    }.freeze

    def self.handle(query)
      # Try to match query against patterns
      tool_info = find_tool_for_query(query)

      unless tool_info
        return {
          error: "Could not parse query. Available patterns:\n" +
                 "  - 'get NIFTY ltp' or 'NIFTY ltp'\n" +
                 "  - 'get NIFTY quote'\n" +
                 "  - 'find instrument NIFTY'\n" +
                 "  - 'get NIFTY option chain' or 'NIFTY option chain'\n" +
                 "  - 'get funds' or 'balance'\n" +
                 "  - 'get positions'\n" +
                 "  - 'get orders'"
        }
      end

      # Extract arguments
      args = tool_info[:extract_args].call(tool_info[:match], query)

      # Resolve symbol to security_id if needed
      args = resolve_symbol_to_security_id(args) if args[:symbol] && !args[:security_id]

      # For option chain, resolve underlying_scrip to integer security_id
      if tool_info[:tool] == "dhan.option.chain" && args[:symbol] && !args[:underlying_scrip].is_a?(Integer)
        args = resolve_symbol_to_security_id_for_option_chain(args)
      end

      # For option chain, if expiry is missing or default, fetch nearest expiry first
      args = resolve_expiry_for_option_chain(args) if tool_info[:tool] == "dhan.option.chain"

      # Call the tool
      result = call_tool(tool_info[:tool], args)

      {
        tool: tool_info[:tool],
        args: args,
        result: result
      }
    end

    private

    def self.find_tool_for_query(query)
      TOOL_PATTERNS.each do |pattern, tool_info|
        match = query.match(pattern)
        return tool_info.merge(match: match) if match
      end
      nil
    end

    def self.resolve_symbol_to_security_id(args)
      # First, try to find instrument to get security_id
      begin
        require_relative "options/complete_integration"
        system = Options::CompleteIntegration.setup_system(dry_run: true)
        registry = system[:registry]

        # Call instrument.find to get security_id
        find_result = registry.call("dhan.instrument.find", {
                                      symbol: args[:symbol],
                                      exchange_segment: args[:exchange_segment]
                                    })

        if find_result[:status] == "success" && find_result[:result]
          security_id = find_result[:result][:security_id] || find_result[:result]["security_id"]
          if security_id
            args[:security_id] = security_id.to_s
            args.delete(:symbol) # Remove symbol, use security_id instead
          end
        end
      rescue StandardError => e
        # If resolution fails, keep original args (tool might handle symbol directly)
      end

      args
    end

    # Resolve symbol to security_id for option chain (needs integer)
    def self.resolve_symbol_to_security_id_for_option_chain(args)
      begin
        require_relative "options/complete_integration"
        system = Options::CompleteIntegration.setup_system(dry_run: true)
        registry = system[:registry]

        # Call instrument.find to get security_id
        find_result = registry.call("dhan.instrument.find", {
                                      symbol: args[:symbol],
                                      exchange_segment: args[:underlying_seg] || "IDX_I"
                                    })

        if find_result[:status] == "success" && find_result[:result]
          security_id = find_result[:result][:security_id] || find_result[:result]["security_id"]
          if security_id
            args[:underlying_scrip] = security_id.to_i # Convert to integer as required by API
            args.delete(:symbol) # Remove symbol, use underlying_scrip instead
          end
        end
      rescue StandardError => e
        # If resolution fails, keep original args
      end

      args
    end

    # Resolve expiry date for option chain - fetches nearest expiry if not provided
    def self.resolve_expiry_for_option_chain(args)
      expiry = args[:expiry] || args["expiry"]
      underlying_scrip = args[:underlying_scrip] || args["underlying_scrip"]
      underlying_seg = args[:underlying_seg] || args["underlying_seg"] || "IDX_I"

      # If expiry is missing or looks like a default/placeholder or invalid, fetch expiries
      expiry_valid = false
      if expiry && !expiry.to_s.empty? && expiry.to_s.match?(/^\d{4}-\d{2}-\d{2}$/)
        begin
          expiry_date = Date.parse(expiry.to_s)
          expiry_valid = expiry_date >= Date.today
        rescue StandardError
          expiry_valid = false
        end
      end

      if expiry.nil? || expiry.to_s.empty? || !expiry_valid
        begin
          require_relative "options/complete_integration"
          system = Options::CompleteIntegration.setup_system(dry_run: true)
          registry = system[:registry]

          # Ensure underlying_scrip is integer
          underlying_scrip = underlying_scrip.to_i if underlying_scrip.respond_to?(:to_i)

          # Call dhan.option.expiries to get available expiries
          # Note: fetch_expiry_list requires an expiry parameter, we'll use today's date
          expiries_result = registry.call("dhan.option.expiries", {
                                            underlying_scrip: underlying_scrip,
                                            underlying_seg: underlying_seg,
                                            expiry: Date.today.strftime("%Y-%m-%d")
                                          })

          if expiries_result[:status] == "success" && expiries_result[:result]
            expiries = expiries_result[:result]
            # Handle different response formats
            expiry_list = if expiries.is_a?(Array)
                            expiries
                          elsif expiries.is_a?(Hash) && (expiries[:expiries] || expiries["expiries"])
                            expiries[:expiries] || expiries["expiries"]
                          else
                            []
                          end

            # Select nearest expiry (first one that's >= today)
            if expiry_list.any?
              today = Date.today
              nearest_expiry = expiry_list
                               .map do |e|
                                 Date.parse(e.to_s)
              rescue StandardError
                nil
              end
                               .compact
                               .select { |d| d >= today }
                               .min

              if nearest_expiry
                args[:expiry] = nearest_expiry.strftime("%Y-%m-%d")
                args["expiry"] = args[:expiry] # Ensure both keys exist
              elsif expiry_list.any?
                # If all expiries are in the past, use the latest one
                latest_expiry = expiry_list
                                .map do |e|
                                  Date.parse(e.to_s)
                rescue StandardError
                  nil
                end
                                .compact
                                .max
                if latest_expiry
                  args[:expiry] = latest_expiry.strftime("%Y-%m-%d")
                  args["expiry"] = args[:expiry]
                end
              end
            end
          end
        rescue StandardError => e
          # If expiry resolution fails, keep original expiry or use default
          if expiry.nil? || expiry.to_s.empty?
            # Default to next week if we can't fetch expiries
            args[:expiry] = (Date.today + 7).strftime("%Y-%m-%d")
            args["expiry"] = args[:expiry]
          end
        end
      end

      args
    end

    def self.call_tool(tool_name, args)
      require_relative "options/complete_integration"
      system = Options::CompleteIntegration.setup_system(dry_run: true)
      registry = system[:registry]

      result = registry.call(tool_name, args)

      if result[:status] == "error"
        {
          error: result[:error],
          tool: tool_name,
          args: args
        }
      else
        # Check if result indicates an error or mock data
        tool_result = result[:result] || {}

        # If LTP is 0, it might be an error or mock data
        if tool_name == "dhan.market.ltp" && tool_result[:ltp] == 0 && !tool_result[:error]
          # Check if DhanHQ is configured
          dhan_configured = defined?(DhanHQ) &&
                            defined?(DhanHQ::Models) &&
                            (defined?(DhanHQ::Models::Funds) || defined?(DhanHQ::Models::Position))

          if !dhan_configured
            tool_result[:warning] =
              "LTP is 0. DhanHQ may not be configured. Set CLIENT_ID and ACCESS_TOKEN environment variables."
          elsif tool_result[:error]
            tool_result[:warning] = "LTP is 0. Error: #{tool_result[:error]}"
          else
            tool_result[:warning] = "LTP is 0. Market may be closed or instrument not found."
          end
        end

        tool_result
      end
    end
  end
end
