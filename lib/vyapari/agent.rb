# frozen_string_literal: true

# Backward compatibility: Vyapari::Agent is now Vyapari::Options::Agent
# This file maintains the old interface for compatibility
# New code should use Vyapari::Runner.run(query) or Vyapari::Options::Agent directly

module Vyapari
  # @deprecated Use Vyapari::Options::Agent or Vyapari::Runner instead
  # Agent class for managing tool interactions with Ollama
  class Agent
    MAX_STEPS = 8

    TOOL_PREREQUISITES = {
      "fetch_intraday_history" => [:instrument],
      "analyze_trend" => [:candles],
      "fetch_expiry_list" => [:instrument],
      "fetch_option_chain" => [:instrument, :trend, :expiry]
    }.freeze

    def initialize(client: Client.new, registry: default_registry, logger: nil)
      @client = client
      @registry = registry
      @messages = []
      @logger = logger || default_logger
      @step = 0
      @tools_called = [] # Track which tools have been called
      @correction_count = {} # Track how many times we've corrected for each tool
      @context = {
        instrument: nil,
        candles: nil,
        trend: nil,
        expiry: nil,
        option_chain: nil
      }
    end

    def run(query)
      # Add system message to guide the workflow
      system_message = {
        role: "system",
        content: <<~PROMPT
          You are an autonomous trading planner.

          RULES:
          - You MUST NOT write Ruby code.
          - You MUST NOT explain in text.
          - You MUST ONLY respond with tool calls until the task is complete.
          - If a required value is missing, request the correct tool.
          - You are NOT allowed to guess.

          CRITICAL: You MUST ONLY use the provided tools. DO NOT write code, DO NOT generate Python scripts, DO NOT hallucinate functions. ONLY call the available tools.

          Available tools: find_instrument, fetch_intraday_history, analyze_trend, fetch_expiry_list, fetch_option_chain, recommend_trade

          You MUST follow this exact stepwise workflow. Call tools ONE AT A TIME, waiting for results before proceeding:

          STEP 1: Call find_instrument tool - For indices (NIFTY, BANKNIFTY), use exchange_segment="IDX_I". For stocks, use NSE_EQ or BSE_EQ.
          STEP 2: Call fetch_intraday_history tool - Parameters are auto-filled from context, call with empty parameters: {}
          STEP 3: Call analyze_trend tool - Parameters are auto-filled from context, call with empty parameters: {}
          STEP 4: Call fetch_expiry_list tool - Parameters are auto-injected from context, call with empty parameters: {}
          STEP 5: Call fetch_option_chain tool - ONLY if step 3 returns trend="bullish" or "bearish" (NOT "avoid"). Parameters are auto-filled from context, call with empty parameters: {}
          STEP 6: Call recommend_trade tool - Parameters are auto-filled from context, call with empty parameters: {}

          ABSOLUTE RULES (NO EXCEPTIONS):
          - NEVER write code or generate scripts (Ruby, Python, or any language)
          - NEVER provide explanations or text responses
          - NEVER say "I'll call X tool" or "Now I will" - just call the tool immediately
          - NEVER guess values - if something is missing, call the prerequisite tool
          - ONLY call the provided tools
          - Call tools ONE AT A TIME, sequentially
          - Wait for each tool's result before calling the next
          - DO NOT provide text responses between tool calls - just call the next tool directly
          - Parameters are automatically resolved from context - you only need to call tools with empty parameters: {}
          - For NIFTY/BANKNIFTY, use exchange_segment="IDX_I" in find_instrument
          - If analyze_trend returns "avoid", skip fetch_expiry_list and fetch_option_chain, go directly to recommend_trade
          - Continue until recommend_trade is called - that's the final step

          Sequence: find_instrument → fetch_intraday_history → analyze_trend → fetch_expiry_list → fetch_option_chain → recommend_trade

          NOTE: If analyze_trend returns trend="avoid", skip fetch_expiry_list and fetch_option_chain, go directly to recommend_trade.

          REMEMBER: You are an autonomous trading planner. Your ONLY job is to call tools. No code. No explanations. No guessing.
        PROMPT
      }

      @messages << system_message
      @messages << { role: "user", content: query }
      @logger.info "🚀 Starting agent with query: #{query}"

      MAX_STEPS.times do |step_num|
        @step = step_num + 1
        @logger.info "\n📊 Step #{@step}/#{MAX_STEPS}"

        response = @client.chat(
          messages: @messages,
          tools: @registry.tool_schemas
        )

        msg = response.fetch("message")
        @messages << msg

        unless msg["tool_calls"]
          # Check if response contains code or is not a final answer
          content = msg["content"].to_s

          # Detect code/hallucination patterns
          is_code = content.include?("import ") || content.include?("def ") || content.include?("function ") ||
                    content.match?(/<\|.*\|>/) || content.include?("pandas") || content.include?("talib") ||
                    content.include?("DataFrame") || content.match?(/^```/) || content.length > 500

          # Detect continuation intent (LLM saying it will call next tool but not actually calling it)
          continuation_phrases = [
            "i'll call", "i will call", "now i'll", "now i will", "next i'll", "next i will",
            "calling", "will call", "going to call", "let me call", "i need to call"
          ]
          is_continuation_intent = continuation_phrases.any? { |phrase| content.downcase.include?(phrase) }

          # Check if workflow is incomplete (not all required tools called)
          workflow_complete = @tools_called.include?("recommend_trade")

          # Check if LLM is providing text response when it should call a tool
          is_text_response = !content.empty? && !is_code && !workflow_complete && content.length < 500

          if is_code || is_continuation_intent || !workflow_complete || is_text_response
            if is_code
              @logger.warn "⚠️  LLM generated code instead of using tools. Forcing continuation..."
            elsif is_continuation_intent
              @logger.warn "⚠️  LLM indicated intent to continue but didn't call tool. Forcing tool call..."
            elsif is_text_response
              @logger.warn "⚠️  LLM provided text response instead of calling tool. Forcing tool call..."
            else
              @logger.warn "⚠️  Workflow incomplete. Forcing continuation..."
            end

            # Provide specific next step based on what's been called
            next_tool = determine_next_tool
            last_result = get_last_tool_result

            # Track correction attempts
            @correction_count[next_tool] ||= 0
            @correction_count[next_tool] += 1

            # If we've corrected 3+ times for the same tool, auto-inject the tool call
            if @correction_count[next_tool] >= 3 && next_tool == "fetch_expiry_list"
              @logger.warn "     🔧 Auto-injecting #{next_tool} tool call after #{@correction_count[next_tool]} failed attempts"

              # Manually inject tool call
              tool_class = @registry.fetch(next_tool)
              resolved_args = resolve_arguments(next_tool, {})
              check_prerequisites(next_tool)

              tool = tool_class.new
              result = tool.call(resolved_args)
              store_in_context(next_tool, result)

              @tools_called << next_tool
              @correction_count[next_tool] = 0 # Reset counter

              @messages << {
                role: "tool",
                tool_call_id: "auto-#{next_tool}-#{Time.now.to_i}",
                content: result.is_a?(String) ? result : result.to_json
              }

              result_summary = result.is_a?(Hash) ? result.keys.join(", ") : result.to_s[0..100]
              @logger.info "     ✅ Auto-injected result: #{result_summary}"
              next
            end

            correction = build_correction_message(next_tool, last_result)

            @messages << {
              role: "user",
              content: correction
            }
            @logger.info "     Correction: #{correction[0..100]}... (attempt #{@correction_count[next_tool]})"
            next
          end

          # Only return if workflow is complete and no continuation intent
          @logger.info "✅ Agent completed. Final response: #{msg["content"]}"
          return msg["content"]
        end

        tool_calls = msg["tool_calls"]

        # CRITICAL: Only process ONE tool at a time to enforce sequential workflow
        if tool_calls.length > 1
          @logger.warn "⚠️  LLM tried to call #{tool_calls.length} tools in parallel. Only processing the first one: #{tool_calls.first["function"]["name"]}"
          @messages << {
            role: "user",
            content: "You called multiple tools at once. You MUST call tools ONE AT A TIME, waiting for each result before calling the next. Only call #{tool_calls.first["function"]["name"]} now."
          }
          tool_calls = [tool_calls.first] # Only process the first tool
        end

        @logger.info "🔧 LLM selected #{tool_calls.length} tool(s): #{tool_calls.map do |tc|
          tc["function"]["name"]
        end.join(", ")}"

        tool_calls.each_with_index do |call, index|
          tool_name = call["function"]["name"]
          arguments = call["function"]["arguments"]
          parsed_args = arguments.is_a?(String) ? JSON.parse(arguments) : arguments

          # Prevent calling the same tool repeatedly
          if @tools_called.last == tool_name && @tools_called.count(tool_name) > 1
            @logger.warn "     ⚠️  Tool #{tool_name} already called. Skipping and guiding to next step..."
            next_tool = determine_next_tool
            @messages << {
              role: "user",
              content: "You already called #{tool_name}. Now call #{next_tool} tool using the results from previous tools."
            }
            break
          end

          @logger.info "\n  🛠️  Tool #{index + 1}/#{tool_calls.length}: #{tool_name}"
          @logger.info "     Parameters: #{parsed_args.inspect}"

          begin
            # Resolve arguments from context (LLM decides tool, Ruby decides args)
            resolved_args = resolve_arguments(tool_name, parsed_args)
            @logger.info "     Resolved Parameters: #{resolved_args.inspect}"

            # Check prerequisites before calling tool
            check_prerequisites(tool_name)

            tool_class = @registry.fetch(tool_name)
            tool = tool_class.new

            result = tool.call(resolved_args)

            # Store result in context
            store_in_context(tool_name, result)

            result_summary = result.is_a?(Hash) ? result.keys.join(", ") : result.to_s[0..100]
            @logger.info "     ✅ Result: #{result_summary}"

            @tools_called << tool_name # Track called tools

            @messages << {
              role: "tool",
              tool_call_id: call["id"],
              content: result.is_a?(String) ? result : result.to_json
            }
          rescue StandardError => e
            @logger.error "     ❌ Error: #{e.message}"

            error_handled = false

            # Special handling for fetch_option_chain errors
            if tool_name == "fetch_option_chain"
              error_msg = e.message.to_s

              # If trend is "avoid", guide to recommend_trade instead
              if error_msg.include?("trend is 'avoid'") || parsed_args["trend"] == "avoid" || parsed_args["trend"].to_s.downcase == "avoid"
                @messages << {
                  role: "user",
                  content: "You tried to call fetch_option_chain with trend='avoid'. DO NOT call fetch_option_chain when trend is 'avoid'. Instead, call recommend_trade with trend='avoid' to get NO_TRADE recommendation."
                }
                @logger.info "     🔄 Redirecting to recommend_trade (trend is avoid)..."
                error_handled = true
                break
              end

              # If symbol is empty, provide specific guidance
              if error_msg.include?("symbol parameter is required") || parsed_args["symbol"].to_s.strip.empty?
                # Try to extract symbol from find_instrument result
                inst_result = @messages.reverse.find do |m|
                  next unless m["role"] == "tool"
                  begin
                    data = JSON.parse(m["content"])
                    data["security_id"] || data["instrument"]
                  rescue JSON::ParserError
                    false
                  end
                end

                if inst_result
                  begin
                    inst_data = JSON.parse(inst_result["content"])
                    symbol_value = inst_data["instrument"] || inst_data["symbol"]

                    # Also get trend from analyze_trend
                    trend_result = @messages.reverse.find do |m|
                      next unless m["role"] == "tool"
                      begin
                        data = JSON.parse(m["content"])
                        data["trend"]
                      rescue JSON::ParserError
                        false
                      end
                    end

                    trend_value = nil
                    if trend_result
                      begin
                        trend_data = JSON.parse(trend_result["content"])
                        trend_value = trend_data["trend"]
                      rescue JSON::ParserError
                        # Continue
                      end
                    end

                    if trend_value == "avoid"
                      @messages << {
                        role: "user",
                        content: "The trend is 'avoid'. DO NOT call fetch_option_chain. Instead, call recommend_trade with trend='avoid' to get NO_TRADE recommendation."
                      }
                    else
                      @messages << {
                        role: "user",
                        content: "The symbol parameter is empty. Use symbol='#{symbol_value}' (from find_instrument result - the 'instrument' field), trend='#{trend_value || "bullish/bearish"}' (from analyze_trend result), and expiry='' for auto-selection."
                      }
                    end
                    @logger.info "     🔄 Providing symbol value: #{symbol_value}..."
                    error_handled = true
                    break
                  rescue JSON::ParserError
                    # Fall through to default error handling
                  end
                end
              end
            end

            # Re-raise the error if we haven't handled it
            raise unless error_handled
          end
        end

        # Log potential next steps
        @logger.info "     🔄 Waiting for LLM to decide next action..."
      end

      raise "Agent did not converge after #{MAX_STEPS} steps"
    end

    private

    def default_registry
      registry = Tools::Registry.new
      registry.register(Tools::RecommendTrade)
      registry.register(Tools::FetchOptionChain)
      registry.register(Tools::AnalyzeTrend)
      registry.register(Tools::FetchIntradayHistory)
      registry.register(Tools::FindInstrument)
      registry.register(Tools::FetchExpiryList)
      registry
    end

    def default_logger
      require "logger"
      logger = Logger.new($stdout)
      logger.level = ENV["VYAPARI_LOG_LEVEL"] ? Logger.const_get(ENV["VYAPARI_LOG_LEVEL"].upcase) : Logger::INFO
      logger.formatter = proc do |_severity, datetime, _progname, msg|
        "[#{datetime.strftime("%H:%M:%S")}] #{msg}\n"
      end
      logger
    end

    def determine_next_tool
      workflow = %w[find_instrument fetch_intraday_history analyze_trend fetch_option_chain recommend_trade]

      # Find the first tool in workflow that hasn't been called
      next_tool = workflow.find { |tool| !@tools_called.include?(tool) }

      # Special handling after analyze_trend
      if @tools_called.include?("analyze_trend")
        # Check analyze_trend result to see if trend was avoid
        # Find the analyze_trend result specifically (look for messages with "trend" field)
        trend_result = @messages.reverse.find do |m|
          next unless m["role"] == "tool"
          begin
            data = JSON.parse(m["content"])
            data["trend"] # This is likely analyze_trend result
          rescue JSON::ParserError
            false
          end
        end

        if trend_result
          begin
            result = JSON.parse(trend_result["content"])
            if result["trend"] == "avoid"
              # Skip fetch_expiry_list and fetch_option_chain if trend is avoid
              return "recommend_trade" unless @tools_called.include?("recommend_trade")
            end
          rescue JSON::ParserError
            # Not JSON, continue
          end
        end
        # If trend is not avoid, need expiry list first, then option chain
        return "fetch_expiry_list" unless @tools_called.include?("fetch_expiry_list")
        return "fetch_option_chain" unless @tools_called.include?("fetch_option_chain")
        return "recommend_trade" unless @tools_called.include?("recommend_trade")
      end

      next_tool || "recommend_trade"
    end

    def get_last_tool_result
      @messages.reverse.find { |m| m["role"] == "tool" }
    end

    def build_correction_message(next_tool, last_result)
      base = "DO NOT write code or generate text. You MUST call the #{next_tool} tool."

      case next_tool
      when "fetch_intraday_history"
        if last_result
          begin
            inst_data = JSON.parse(last_result["content"])
            instrument_value = inst_data["instrument"] || inst_data["instrument_type"]
            base += " Use security_id=#{inst_data["security_id"]}, exchange_segment='#{inst_data["exchange_segment"]}', instrument='#{instrument_value}', interval='5' (as a string)."
          rescue JSON::ParserError
            base += " Use security_id, exchange_segment, and instrument (NOT instrument_type) from find_instrument result, and interval='5' (as a string)."
          end
        else
          base += " Use security_id, exchange_segment, and instrument from find_instrument result, and interval='5' (as a string)."
        end
      when "analyze_trend"
        if last_result
          begin
            hist_data = JSON.parse(last_result["content"])
            if hist_data["candles"] && !hist_data["candles"].empty?
              base += " Use the 'candles' array from fetch_intraday_history result. The candles field contains an array of candle objects. Pass the entire candles array (not a string representation)."
            else
              base += " The fetch_intraday_history returned empty candles. This means no data is available. You should still call analyze_trend with the empty array - it will return 'avoid' trend."
            end
          rescue JSON::ParserError
            base += " Use the 'candles' array from fetch_intraday_history result. Extract the 'candles' field (which is an array) and pass it directly."
          end
        else
          base += " Use the 'candles' array from fetch_intraday_history result. Extract the 'candles' field (which is an array) and pass it directly."
        end
      when "fetch_option_chain"
        # Extract symbol from find_instrument and trend from analyze_trend
        symbol_value = nil
        trend_value = nil

        # Find find_instrument result (look for messages with security_id or instrument field)
        @messages.reverse.each do |msg|
          next unless msg["role"] == "tool"
          begin
            data = JSON.parse(msg["content"])
            if data["security_id"] || data["instrument"] # This is likely find_instrument result
              symbol_value = data["instrument"] || data["symbol"]
              break if symbol_value
            end
          rescue JSON::ParserError
            # Not JSON, continue
          end
        end

        # Find analyze_trend result (look for messages with trend field)
        trend_value = nil
        @messages.reverse.each do |msg|
          next unless msg["role"] == "tool"
          begin
            data = JSON.parse(msg["content"])
            if data["trend"] # This is likely analyze_trend result
              trend_value = data["trend"]
              break if trend_value
            end
          rescue JSON::ParserError
            # Not JSON, continue
          end
        end

        if symbol_value && trend_value
          if trend_value == "avoid"
            base = "DO NOT call fetch_option_chain when trend is 'avoid'. Instead, call recommend_trade with trend='avoid' to get NO_TRADE recommendation."
          else
            base += " Use symbol='#{symbol_value}' (from find_instrument result - the 'instrument' field), trend='#{trend_value}' (from analyze_trend result), and expiry='' (empty string for auto-selection). DO NOT pass exchange_segment, instrument, security_id, candles, interval, or strike_price."
          end
        else
          if trend_value == "avoid"
            base = "DO NOT call fetch_option_chain when trend is 'avoid'. Instead, call recommend_trade with trend='avoid' to get NO_TRADE recommendation."
          else
            base += " Use symbol from find_instrument result (the 'instrument' field - NOT empty string), trend from analyze_trend result (the 'trend' field - must be 'bullish' or 'bearish', NOT 'avoid'), and expiry='' (empty string for auto-selection). DO NOT pass exchange_segment, instrument, security_id, candles, interval, or strike_price."
          end
        end
      when "fetch_expiry_list"
        base = "You MUST call the fetch_expiry_list tool NOW. Parameters (symbol, security_id, exchange_segment) are automatically injected from context - just call the tool with empty parameters: {}. Do not provide any text response, just call the tool."
      when "recommend_trade"
        base += " Use options from fetch_option_chain and trend from analyze_trend."
      end

      base
    end

    def resolve_arguments(tool_name, args)
      case tool_name
      when "find_instrument"
        # LLM provides these, use as-is
        args

      when "fetch_intraday_history"
        # Inject from context - LLM params are completely ignored
        raise "Missing instrument context" unless @context[:instrument]
        {
          "security_id" => @context[:instrument]["security_id"] || @context[:instrument][:security_id],
          "exchange_segment" => @context[:instrument]["exchange_segment"] || @context[:instrument][:exchange_segment],
          "instrument" => @context[:instrument]["instrument"] || @context[:instrument][:instrument],
          "interval" => "5" # Fixed value, LLM args ignored
        }

      when "analyze_trend"
        # Inject candles from context - LLM params are ignored
        raise "Missing candles context" unless @context[:candles]
        { "candles" => @context[:candles] }

      when "fetch_expiry_list"
        # Inject underlying_seg and underlying_scrip from context
        raise "Missing instrument context" unless @context[:instrument]
        inst = @context[:instrument]
        underlying_seg = inst["exchange_segment"] || inst[:exchange_segment] || "IDX_I"
        underlying_scrip = inst["security_id"] || inst[:security_id]
        # Use stored symbol (original user input like "NIFTY"), not instrument type ("INDEX")
        symbol = inst["symbol"] || inst[:symbol] || inst["instrument"] || inst[:instrument]

        # Provide both underlying_scrip (for OptionChain.fetch_expiry_list) and symbol (for fallback)
        args = {
          "underlying_seg" => underlying_seg
        }
        args["underlying_scrip"] = underlying_scrip.to_i if underlying_scrip
        args["symbol"] = symbol if symbol

        raise "Missing both security_id and symbol in instrument context" unless underlying_scrip || symbol

        args

      when "fetch_option_chain"
        # Inject all from context - LLM params are ignored
        raise "Missing instrument context" unless @context[:instrument]
        raise "Missing trend context" unless @context[:trend]
        raise "Missing expiry context" unless @context[:expiry]

        inst = @context[:instrument]
        underlying_seg = inst["exchange_segment"] || inst[:exchange_segment] || "IDX_I"
        underlying_scrip = inst["security_id"] || inst[:security_id]
        # Use stored symbol (original user input like "NIFTY"), not instrument type ("INDEX")
        symbol = inst["symbol"] || inst[:symbol] || inst["instrument"] || inst[:instrument]

        raise "Missing security_id in instrument context" unless underlying_scrip

        {
          "underlying_seg" => underlying_seg,
          "underlying_scrip" => underlying_scrip.to_i,
          "symbol" => symbol, # Keep for fallback
          "expiry" => @context[:expiry],
          "trend" => @context[:trend]
        }

      when "recommend_trade"
        # Inject all from context - LLM params are ignored
        raise "Missing trend context" unless @context[:trend]
        raise "Missing option_chain context" unless @context[:option_chain]
        { "trend" => @context[:trend], "options" => @context[:option_chain] }

      else
        args
      end
    end

    def check_prerequisites(tool_name)
      required = TOOL_PREREQUISITES[tool_name] || []
      return if required.empty?

      # Check if context keys are present (not nil)
      # In plain Ruby, we check for truthiness (nil and false are falsy)
      missing = required.reject { |k| @context[k] }
      return if missing.empty?

      missing_keys = missing.join(", ")
      raise "Tool #{tool_name} called without required context: #{missing_keys}. Call prerequisite tools first."
    end

    def store_in_context(tool_name, result)
      case tool_name
      when "find_instrument"
        @context[:instrument] = result.is_a?(Hash) ? result : JSON.parse(result)

      when "fetch_intraday_history"
        data = result.is_a?(Hash) ? result : JSON.parse(result)
        @context[:candles] = data["candles"] || data[:candles] || data

      when "analyze_trend"
        data = result.is_a?(Hash) ? result : JSON.parse(result)
        @context[:trend] = data["trend"] || data[:trend]

      when "fetch_expiry_list"
        # Store first valid expiry (handles expiry_passed logic)
        expiries = result.is_a?(Array) ? result : JSON.parse(result)
        return unless expiries.any?

        # Check if first expiry has passed (after 4 PM on expiry day)
        first_expiry = expiries.first
        if expiry_passed?(first_expiry)
          # Use second expiry if first has passed
          @context[:expiry] = expiries[1] if expiries.length > 1
        else
          @context[:expiry] = first_expiry
        end

      when "fetch_option_chain"
        @context[:option_chain] = result.is_a?(Hash) ? result : JSON.parse(result)
      end
    end

    def expiry_passed?(expiry_date_str)
      return false if expiry_date_str.nil? || expiry_date_str.empty?

      require "date"
      require "time"

      expiry_date = Date.parse(expiry_date_str)
      today = Date.today
      current_time = Time.now

      # Check if expiry is today and it's past 4 PM (16:00)
      if expiry_date == today
        current_time.hour >= 16
      else
        # Check if expiry date is in the past
        expiry_date < today
      end
    rescue Date::Error
      false
    end

    attr_reader :client, :registry, :messages, :logger, :step, :tools_called, :context
  end
end
