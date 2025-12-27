# frozen_string_literal: true

module Vyapari
  # Mode router that deterministically routes queries to the appropriate trading mode
  class Runner
    def self.run(query)
      mode = detect_mode(query)

      case mode
      when :tool_query
        # Direct tool query (data APIs)
        run_tool_query(query)
      when :options
        # Use new PhasedAgent system
        run_phased_options_agent(query)
      when :swing
        Swing::Agent.new.run(query)
      else
        raise Error, "Unsupported trading mode detected"
      end
    end

    def self.detect_mode(query)
      # Check for simple tool queries first (data APIs)
      # These are direct data API calls, not trading workflows
      tool_query_patterns = [
        /\b(get|fetch|show|what|list|find)\s+(?:me\s+)?(?:the\s+)?/i, # "get", "fetch", "show me", "what is", "list"
        /\b(ltp|price|quote|ohlc|candles?|option\s+chain|funds?|balance|margin|positions?|orders?)\b/i, # Tool keywords
        /\b(intraday|historical|1m|5m|15m|1min|5min|15min)\s+(?:ohlc|candles?|data)\b/i, # Historical data queries
        /^\s*(what|show|get|fetch|list)\s+/i # Starts with query words
      ]

      return :tool_query if tool_query_patterns.any? { |pattern| query.match?(pattern) }

      # Deterministic rule-based detection (no LLM guessing)
      # Only route to options if it's clearly a trading workflow, not a data query
      if query.match?(/\b(analyze|trade|buy|sell|entry|exit|stoploss|target)\b/i) &&
         query.match?(/option|ce|pe|expiry/i)
        return :options
      end

      :swing
    end

    # Handle direct tool queries (data APIs)
    def self.run_tool_query(query)
      require_relative "tool_query_handler"
      result = ToolQueryHandler.handle(query)
      format_tool_result(result)
    end

    # Run options trading using the new PhasedAgent system
    def self.run_phased_options_agent(query)
      require_relative "options/complete_integration"

      # Use CompleteIntegration to set up and run the phased agent
      result = Options::CompleteIntegration.run_complete_workflow(
        task: query,
        dry_run: ENV.fetch("DRY_RUN", "true") == "true"
      )

      # Format result for CLI output
      format_result(result[:result])
    end

    # Format the result for CLI display
    def self.format_result(result)
      return "No result" unless result

      output = []
      output << "\n" + "=" * 70
      output << "TRADING ANALYSIS RESULT"
      output << "=" * 70

      if result[:final_status]
        output << "\nStatus: #{result[:final_status].upcase}"
        output << "Output: #{result[:final_output]}" if result[:final_output]
      end

      if result[:phases]
        output << "\nPhase Results:"
        result[:phases].each do |phase, phase_result|
          next unless phase_result.is_a?(Hash)

          output << "\n  #{phase.to_s.upcase}:"
          output << "    Status: #{phase_result[:status]}" if phase_result[:status]
          if phase_result[:iterations]
            output << "    Iterations: #{phase_result[:iterations]}/#{phase_result[:max_iterations]}"
          end
        end
      end

      output << "\nOrder ID: #{result[:order_id]}" if result[:order_id]

      output << "\n" + "=" * 70
      output.join("\n")
    end

    # Format tool query result for CLI display
    def self.format_tool_result(result)
      return result[:error] if result[:error]

      output = []
      output << "\n" + "=" * 70
      output << "TOOL RESULT"
      output << "=" * 70
      output << "\nTool: #{result[:tool]}"
      output << "Arguments: #{result[:args].inspect}"

      # Check DhanHQ configuration status
      dhan_configured = defined?(DhanHQ) &&
                        defined?(DhanHQ::Models) &&
                        (defined?(DhanHQ::Models::Funds) || defined?(DhanHQ::Models::Position))

      if dhan_configured
        output << "DhanHQ: ✅ Configured (using REAL API)"
      else
        output << "DhanHQ: ⚠️  Not configured (using MOCK data)"
        output << "        Set CLIENT_ID and ACCESS_TOKEN to use real API"
      end

      output << "\nResult:"

      if result[:result].is_a?(Hash)
        # Show error first if present
        if result[:result][:error] || result[:result]["error"]
          error_msg = result[:result][:error] || result[:result]["error"]
          output << "\n❌ ERROR: #{error_msg}"
        end

        # Show warning if present
        if result[:result][:warning] || result[:result]["warning"]
          warning_msg = result[:result][:warning] || result[:result]["warning"]
          output << "\n⚠️  WARNING: #{warning_msg}"
        end

        result[:result].each do |key, value|
          # Skip error and warning (already shown above)
          next if [:error, "error", :warning, "warning"].include?(key)

          if value.is_a?(Array)
            output << "  #{key}: [#{value.length} items]"
            # For option chain contracts, show more details
            if key.to_s == "contracts" && value.any?
              value.each_with_index do |item, idx|
                if item.is_a?(Hash)
                  # Format contract nicely
                  strike = item[:strike] || item["strike"]
                  type = item[:type] || item["type"]
                  ltp = item[:ltp] || item["ltp"]
                  bid = item[:bid] || item["bid"]
                  ask = item[:ask] || item["ask"]
                  oi = item[:open_interest] || item["open_interest"]
                  delta = item[:delta] || item["delta"]
                  iv = item[:implied_volatility] || item["implied_volatility"]
                  quality = item[:quality_score] || item["quality_score"]

                  contract_str = "[#{idx + 1}] Strike: #{strike}, Type: #{type}, LTP: #{ltp}, Bid: #{bid}, Ask: #{ask}"
                  contract_str += ", OI: #{oi}" if oi && oi > 0
                  contract_str += ", Delta: #{delta.round(3)}" if delta && delta != 0
                  contract_str += ", IV: #{iv.round(2)}%" if iv && iv > 0
                  contract_str += ", Quality: #{quality.round(1)}" if quality
                  output << "    #{contract_str}"
                else
                  output << "    [#{idx + 1}] #{item.inspect}"
                end
              end
            else
              # For other arrays, show first 10 items
              value.first(10).each_with_index do |item, idx|
                output << "    [#{idx + 1}] #{item.inspect}"
              end
              output << "    ... (#{value.length - 10} more)" if value.length > 10
            end
          elsif value.is_a?(Hash)
            output << "  #{key}:"
            value.each { |k, v| output << "    #{k}: #{v.inspect}" }
          else
            output << "  #{key}: #{value.inspect}"
          end
        end
      else
        output << "  #{result[:result].inspect}"
      end

      output << "\n" + "=" * 70
      output.join("\n")
    end
  end
end
