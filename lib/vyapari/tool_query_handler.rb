# frozen_string_literal: true

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
          # Try to extract expiry from query, default to next week
          expiry_match = query.match(/(\d{4}-\d{2}-\d{2})|expiry[:\s]+(\d{4}-\d{2}-\d{2})/i)
          expiry = expiry_match ? (expiry_match[1] || expiry_match[2]) : (Date.today + 7).strftime("%Y-%m-%d")

          {
            underlying_scrip: underlying,
            underlying_seg: "IDX_I",
            expiry: expiry
          }
        }
      },
      /(\w+)\s+option\s+chain/i => {
        tool: "dhan.option.chain",
        extract_args: lambda { |match, query|
          underlying = match[1]
          expiry_match = query.match(/(\d{4}-\d{2}-\d{2})|expiry[:\s]+(\d{4}-\d{2}-\d{2})/i)
          expiry = expiry_match ? (expiry_match[1] || expiry_match[2]) : (Date.today + 7).strftime("%Y-%m-%d")

          {
            underlying_scrip: underlying,
            underlying_seg: "IDX_I",
            expiry: expiry
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
