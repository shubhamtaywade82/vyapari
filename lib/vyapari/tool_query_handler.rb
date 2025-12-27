# frozen_string_literal: true

require "date"

# LLM-powered tool query handler for direct data API calls
# Uses Ollama agent to understand natural language and route to appropriate tools
# Allows testing individual tools without going through full trading workflow
module Vyapari
  class ToolQueryHandler
    # Legacy pattern matching (kept for backward compatibility)
    # LLM-based routing is now the primary method
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
      },
      # Intraday historical data patterns
      /get\s+(\w+)\s+intraday\s+(\d+)\s*(?:min|m|minute|minutes)?/i => {
        tool: "dhan.history.intraday",
        extract_args: lambda { |match, query|
          symbol = match[1]
          interval = match[2]
          # Extract dates if provided, otherwise use defaults
          from_date_match = query.match(/from[:\s]+(\d{4}-\d{2}-\d{2})/i)
          to_date_match = query.match(/to[:\s]+(\d{4}-\d{2}-\d{2})/i)

          from_date = from_date_match ? from_date_match[1] : nil
          to_date = to_date_match ? to_date_match[1] : nil

          {
            symbol: symbol,
            exchange_segment: symbol.match?(/NIFTY|BANKNIFTY|SENSEX/i) ? "IDX_I" : "NSE_EQ",
            interval: interval,
            from_date: from_date,
            to_date: to_date
          }
        }
      },
      /get\s+(\w+)\s+historical\s+intraday\s+(\d+)\s*(?:min|m|minute|minutes)?/i => {
        tool: "dhan.history.intraday",
        extract_args: lambda { |match, query|
          symbol = match[1]
          interval = match[2]
          from_date_match = query.match(/from[:\s]+(\d{4}-\d{2}-\d{2})/i)
          to_date_match = query.match(/to[:\s]+(\d{4}-\d{2}-\d{2})/i)

          from_date = from_date_match ? from_date_match[1] : nil
          to_date = to_date_match ? to_date_match[1] : nil

          {
            symbol: symbol,
            exchange_segment: symbol.match?(/NIFTY|BANKNIFTY|SENSEX/i) ? "IDX_I" : "NSE_EQ",
            interval: interval,
            from_date: from_date,
            to_date: to_date
          }
        }
      },
      /(\w+)\s+intraday\s+(\d+)\s*(?:min|m|minute|minutes)?/i => {
        tool: "dhan.history.intraday",
        extract_args: lambda { |match, query|
          symbol = match[1]
          interval = match[2]
          from_date_match = query.match(/from[:\s]+(\d{4}-\d{2}-\d{2})/i)
          to_date_match = query.match(/to[:\s]+(\d{4}-\d{2}-\d{2})/i)

          from_date = from_date_match ? from_date_match[1] : nil
          to_date = to_date_match ? to_date_match[1] : nil

          {
            symbol: symbol,
            exchange_segment: symbol.match?(/NIFTY|BANKNIFTY|SENSEX/i) ? "IDX_I" : "NSE_EQ",
            interval: interval,
            from_date: from_date,
            to_date: to_date
          }
        }
      }
    }.freeze

    def self.handle(query)
      # PRIMARY: Try LLM-based routing (understands natural language)
      llm_result = route_with_llm(query)
      return llm_result if llm_result && !llm_result[:error]

      # FALLBACK: Pattern matching for backward compatibility
      tool_info = find_tool_for_query(query)

      unless tool_info
        return {
          error: "Could not parse query. Try natural language like:\n" +
                 "  - 'What is NIFTY's current price?'\n" +
                 "  - 'Get NIFTY option chain'\n" +
                 "  - 'Show me NIFTY 5 minute candles'\n" +
                 "  - 'What's my account balance?'\n" +
                 "  - 'List my positions'\n" +
                 "  - 'Show my orders'"
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

      # For intraday historical, resolve symbol and set up dates
      args = resolve_intraday_historical_args(args) if tool_info[:tool] == "dhan.history.intraday"

      # Call the tool
      result = call_tool(tool_info[:tool], args)

      {
        tool: tool_info[:tool],
        args: args,
        result: result
      }
    end

    private

    # Use LLM to understand query and route to appropriate tool
    def self.route_with_llm(query)
      require_relative "options/complete_integration"
      system = Options::CompleteIntegration.setup_system(dry_run: true)
      registry = system[:registry]

      # Create a simple agent for tool routing
      require_relative "../ollama/agent"
      agent = Ollama::Agent.new(
        registry: registry,
        max_iterations: 4, # Allow multiple iterations for multi-step calls (instrument.find → target tool)
        timeout: 20
      )

      # Create a routing prompt
      routing_prompt = <<~PROMPT
        User wants to call a data API tool. Understand their query and call the appropriate tool.

        User query: "#{query}"

        Instructions:
        1. Identify which tool matches the user's intent
        2. Extract all required arguments from the query
        3. For tools that need security_id, you MUST first call dhan.instrument.find to resolve the symbol
        4. Call the target tool with ALL required arguments
        5. Return the tool's result

        CRITICAL RULES:
        - dhan.instrument.find REQUIRES: symbol AND exchange_segment
          * For indices (NIFTY, BANKNIFTY, SENSEX): exchange_segment = "IDX_I"
          * For stocks: exchange_segment = "NSE_EQ" or "BSE_EQ"
        - dhan.market.ltp REQUIRES: security_id AND exchange_segment (get from instrument.find first)
        - dhan.history.intraday REQUIRES: security_id, exchange_segment, instrument, interval, from_date, to_date
        - dhan.option.chain REQUIRES: underlying_scrip (integer security_id), underlying_seg, expiry

        Examples:
        - "get NIFTY ltp" or "NIFTY price" →
          1. Call dhan.instrument.find with symbol="NIFTY", exchange_segment="IDX_I"
          2. Use the security_id from result
          3. Call dhan.market.ltp with security_id and exchange_segment="IDX_I"

        - "NIFTY option chain" →
          1. Call dhan.instrument.find with symbol="NIFTY", exchange_segment="IDX_I"
          2. Use security_id as underlying_scrip (convert to integer)
          3. Call dhan.option.chain with underlying_scrip, underlying_seg="IDX_I", expiry (auto-resolve if needed)

        - "NIFTY intraday 5min" →
          1. Call dhan.instrument.find with symbol="NIFTY", exchange_segment="IDX_I"
          2. Get security_id and instrument_type from result
          3. Call dhan.history.intraday with security_id, exchange_segment="IDX_I", instrument, interval="5", dates

        - "my balance" or "funds" → call dhan.funds.balance (no args needed)
        - "show positions" → call dhan.positions.list (no args needed)
        - "orders" → call dhan.orders.list (no args needed)

        For intraday queries:
        - Extract interval (e.g., "5min" → "5", "15min" → "15", "1m" → "1")
        - Set to_date to today (or last trading day if weekend) in YYYY-MM-DD format
        - Set from_date to last trading day before to_date in YYYY-MM-DD format
        - instrument_type from instrument.find result (usually "INDEX" for NIFTY)

        IMPORTANT: Always provide ALL required fields. Never skip exchange_segment or other required parameters.

        Call the tool(s) now.
      PROMPT

      # Run agent with routing task
      # The agent.loop method runs the agent loop and returns a result hash
      result = agent.loop(task: routing_prompt)

      # Debug: Log result structure if needed
      # puts "DEBUG: Agent result: #{result.inspect}" if ENV["DEBUG"]

      # Extract tool call from agent result
      # Handle various status values: completed, max_iterations, timeout, etc.
      if result && result[:status]
        # Extract from trace - find all tool calls
        trace = result[:trace] || []
        tool_calls = trace.select { |t| t[:tool_call] }

        # Get the last successful tool call (the one that produced the final result)
        # Skip instrument.find calls - we want the actual target tool
        target_tool_calls = tool_calls.reject do |t|
          tool_name = t[:tool_call]&.dig(:tool) || t[:tool_call]&.dig("tool")
          tool_name == "dhan.instrument.find"
        end

        last_tool_call = target_tool_calls.last || tool_calls.last || trace.reverse.find do |t|
          t[:tool_call] || t[:result]
        end

        if last_tool_call
          tool_call = last_tool_call[:tool_call] || {}
          tool_name = tool_call[:tool] || tool_call["tool"] || "unknown"
          tool_args = tool_call[:args] || tool_call["args"] || {}

          # Get result from context (last item) or from the tool call result
          context = result[:context] || []
          tool_result = last_tool_call[:result] || context.last || result[:reason] || {}

          # If result is an error, extract error message
          if tool_result.is_a?(Hash) && (tool_result[:status] == "error" || tool_result["status"] == "error")
            error_msg = tool_result[:error] || tool_result["error"] || "Tool execution failed"
            return {
              error: error_msg,
              tool: tool_name,
              args: tool_args,
              result: tool_result
            }
          end

          # Return successful result
          return {
            tool: tool_name,
            args: tool_args,
            result: tool_result.is_a?(Hash) ? tool_result : { output: tool_result }
          }
        elsif result[:reason]
          # If no tool call but we have a reason, might be a final answer
          return {
            tool: "final",
            args: {},
            result: { output: result[:reason] }
          }
        end

        # If we have a result but couldn't extract tool call, check if it's an error status
        if %w[error verification_failed timeout].include?(result[:status])
          return {
            error: result[:reason] || "LLM routing failed: #{result[:status]}",
            tool: nil,
            args: {},
            result: nil
          }
        end
      end

      # If LLM routing didn't produce a clear result, return nil to fall back to patterns
      nil
    rescue StandardError => e
      # If LLM routing fails, fall back to pattern matching
      nil
    end

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

    # Resolve arguments for intraday historical data
    def self.resolve_intraday_historical_args(args)
      # First, resolve symbol to security_id and get instrument type
      if args[:symbol] && !args[:security_id]
        begin
          require_relative "options/complete_integration"
          system = Options::CompleteIntegration.setup_system(dry_run: true)
          registry = system[:registry]

          # Call instrument.find to get security_id and instrument type
          find_result = registry.call("dhan.instrument.find", {
                                        symbol: args[:symbol],
                                        exchange_segment: args[:exchange_segment]
                                      })

          if find_result[:status] == "success" && find_result[:result]
            result = find_result[:result]
            args[:security_id] = (result[:security_id] || result["security_id"]).to_s
            args[:instrument] = result[:instrument_type] || result["instrument_type"] || "INDEX"
            args.delete(:symbol) # Remove symbol, use security_id instead
          end
        rescue StandardError => e
          # If resolution fails, use defaults
          args[:instrument] = args[:exchange_segment] == "IDX_I" ? "INDEX" : "EQUITY"
        end
      end

      # Set up dates if not provided
      today = Date.today

      # Find last trading day (skip weekends)
      last_trading_day = today
      last_trading_day = last_trading_day.prev_day while last_trading_day.saturday? || last_trading_day.sunday?

      # If today is weekend, use Friday
      if today.saturday? || today.sunday?
        last_trading_day = today.prev_day
        last_trading_day = last_trading_day.prev_day while last_trading_day.saturday? || last_trading_day.sunday?
      end

      # Set default dates following production-grade rules
      # LIVE mode: from_date = last trading day before to_date, to_date = today (if trading day) or last trading day
      if args[:to_date].nil? || args[:to_date].to_s.empty?
        # Use today if it's a trading day, otherwise use last trading day
        to_date = today.saturday? || today.sunday? ? last_trading_day : today
        args[:to_date] = to_date.strftime("%Y-%m-%d")
      end

      if args[:from_date].nil? || args[:from_date].to_s.empty?
        # In LIVE mode, from_date should be the last trading day before to_date
        to_dt = Date.parse(args[:to_date])
        from_dt = to_dt.prev_day
        # Skip weekends
        from_dt = from_dt.prev_day while from_dt.saturday? || from_dt.sunday?
        args[:from_date] = from_dt.strftime("%Y-%m-%d")
      end

      # Ensure interval is a string
      args[:interval] = args[:interval].to_s if args[:interval]

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
