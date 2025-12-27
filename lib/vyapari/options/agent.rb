# frozen_string_literal: true

require "json"

module Vyapari
  module Options
    # Options trading agent - handles options buying workflow
    class Agent
      MAX_STEPS = 50 # Safety limit to prevent infinite loops

      TOOL_PREREQUISITES = {
        "fetch_intraday_history" => [:instrument],
        "analyze_structure_15m" => [:candles_15m],
        "analyze_trend" => [:candles],
        "fetch_expiry_list" => [:instrument],
        "fetch_option_chain" => %i[instrument trend expiry],
        "recommend_trade" => [:trend] # option_chain is optional when trend is "avoid"
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
          candles_15m: nil,
          structure_15m: nil,
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
            You are an autonomous options trading planner.

            RULES:
            - You MUST NOT write Ruby code.
            - You MUST NOT explain in text.
            - You MUST ONLY respond with tool calls until the task is complete.
            - If a required value is missing, request the correct tool.
            - You are NOT allowed to guess.

            CRITICAL: You MUST ONLY use the provided tools. DO NOT write code, DO NOT generate Python scripts, DO NOT hallucinate functions. ONLY call the available tools.

            Available tools: find_instrument, fetch_intraday_history, analyze_structure_15m, analyze_trend, fetch_expiry_list, fetch_option_chain, recommend_trade

            You MUST follow this exact stepwise workflow. Call tools ONE AT A TIME, waiting for results before proceeding:

            STEP 1: Call find_instrument tool - For indices (NIFTY, BANKNIFTY), use exchange_segment="IDX_I". For stocks, use NSE_EQ or BSE_EQ.
            STEP 2: Call fetch_intraday_history tool with interval="15" to fetch 15-minute candles - Parameters are auto-filled from context, but you MUST specify interval="15" for 15m candles
            STEP 2A: Call analyze_structure_15m tool - Analyzes 15m structure. Returns: bullish, bearish, or range. If result is 'range' (valid=false), STOP and call recommend_trade with NO_TRADE. Parameters are auto-filled from context, call with empty parameters: {}
            STEP 3: Call fetch_intraday_history tool with interval="5" to fetch 5-minute candles - Parameters are auto-filled from context, but you MUST specify interval="5" for 5m candles
            STEP 4: Call analyze_trend tool - Parameters are auto-filled from context, call with empty parameters: {}
            STEP 5: Call fetch_expiry_list tool - Parameters are auto-injected from context, call with empty parameters: {}
            STEP 6: Call fetch_option_chain tool - Parameters are auto-filled from context, call with empty parameters: {}
            STEP 7: Call recommend_trade tool - Parameters are auto-filled from context, call with empty parameters: {}

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
            - You can call fetch_option_chain even if analyze_trend returns "avoid"
            - Continue until recommend_trade is called - that's the final step

            Sequence: find_instrument → fetch_intraday_history(15m) → analyze_structure_15m → fetch_intraday_history(5m) → analyze_trend → fetch_expiry_list → fetch_option_chain → recommend_trade

            CRITICAL: If analyze_structure_15m returns structure="range" (valid=false), STOP immediately and call recommend_trade with NO_TRADE. Do NOT proceed to analyze_trend or fetch_option_chain.

            NOTE: You can call fetch_option_chain even if trend is "avoid" - it will still fetch the option chain data.

            FINAL RESPONSE RULES:
            - When the workflow is complete (after recommend_trade is called), provide a concise summary of the analysis and the trade recommendation.
            - If the recommendation is NO_TRADE, explain why based on the analysis (e.g., "Market is choppy due to low ADX and unclear EMA alignment").
            - DO NOT provide generic responses like "I cannot provide financial advice." or "Is there anything else I can help you with?".
            - Your final response MUST be a direct summary of the analysis and recommendation based on available facts.
            - Include key indicators (RSI, ADX, EMA, volume trends) and their interpretation in your final response.

            REMEMBER: You are an autonomous trading planner. Your ONLY job is to call tools until recommend_trade completes, then provide analysis insights. No code. No generic refusals. Provide actionable insights based on available facts.
          PROMPT
        }

        @messages << system_message
        @messages << { role: "user", content: query }
        @logger.info "🚀 Starting options agent with query: #{query}"

        # Dynamic loop: continue until recommend_trade is called or max steps reached
        @step = 0
        while @step < MAX_STEPS
          @step += 1
          @logger.info "\n📊 Step #{@step} (max: #{MAX_STEPS})"

          # Check if recommend_trade has been called - if so, we're done
          if @tools_called.include?("recommend_trade")
            @logger.info "✅ recommend_trade called - workflow complete"
            break
          end

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

              # If we've corrected 3+ times for critical tools, auto-inject the tool call
              # Critical tools that can be auto-injected: analyze_trend, fetch_expiry_list, analyze_structure_15m
              auto_injectable_tools = %w[analyze_trend fetch_expiry_list analyze_structure_15m]

              if @correction_count[next_tool] >= 3 && auto_injectable_tools.include?(next_tool)
                @logger.warn "     🔧 Auto-injecting #{next_tool} tool call after #{@correction_count[next_tool]} failed attempts"

                begin
                  # Manually inject tool call
                  tool_class = @registry.fetch(next_tool)
                  resolved_args = resolve_arguments(next_tool, {})
                  check_prerequisites(next_tool)

                  tool = tool_class.new
                  result = tool.call(resolved_args)
                  store_in_context(next_tool, result, resolved_args)

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
                rescue StandardError => e
                  @logger.error "     ❌ Auto-injection failed for #{next_tool}: #{e.message}"
                  # Fall through to correction message
                end
              end

              correction = build_correction_message(next_tool, last_result)

              @messages << {
                role: "user",
                content: correction
              }
              @logger.info "     Correction: #{correction[0..100]}... (attempt #{@correction_count[next_tool]})"
              next
            end

            # Only return if workflow is complete (recommend_trade called) and no continuation intent
            if @tools_called.include?("recommend_trade")
              content_length = msg["content"].to_s.length
              @logger.info "✅ Options agent completed. Final response length: #{content_length} chars"
              return msg["content"]
            else
              # Workflow not complete - continue loop
              @logger.warn "⚠️  LLM provided text response but recommend_trade not called. Continuing..."
              next
            end
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
              # Check prerequisites before resolving arguments
              check_prerequisites(tool_name)

              # Resolve arguments from context (LLM decides tool, Ruby decides args)
              resolved_args = resolve_arguments(tool_name, parsed_args)
              @logger.info "     Resolved Parameters: #{resolved_args.inspect}"

              tool_class = @registry.fetch(tool_name)
              tool = tool_class.new

              result = tool.call(resolved_args)

              # Store result in context (pass resolved_args to track interval for fetch_intraday_history)
              store_in_context(tool_name, result, resolved_args)

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

              # Special handling for analyze_structure_15m errors
              if tool_name == "analyze_structure_15m"
                error_msg = e.message.to_s
                if error_msg.include?("Missing candles_15m") || error_msg.include?("candles_15m")
                  @messages << {
                    role: "user",
                    content: "You tried to call analyze_structure_15m but 15-minute candles are missing. You MUST call fetch_intraday_history with interval='15' first to fetch 15-minute candles. Call fetch_intraday_history with interval='15' now."
                  }
                  @logger.info "     🔄 Guiding to fetch_intraday_history with interval='15'..."
                  error_handled = true
                  break
                end
              end

              # Special handling for fetch_option_chain errors
              if tool_name == "fetch_option_chain"
                error_msg = e.message.to_s

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

                      # Allow fetch_option_chain even with "avoid" trend
                      @messages << {
                        role: "user",
                        content: "The symbol parameter is empty. Use symbol='#{symbol_value}' (from find_instrument result - the 'instrument' field), trend='#{trend_value || "bullish/bearish"}' (from analyze_trend result), and expiry='' for auto-selection."
                      }
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

        # Check if recommend_trade was called
        unless @tools_called.include?("recommend_trade")
          raise "Options agent did not complete workflow after #{@step} steps. recommend_trade was not called."
        end

        @logger.info "✅ Options agent completed successfully after #{@step} steps"
        # Get the last tool result (recommend_trade)
        last_tool_result = get_last_tool_result
        if last_tool_result
          begin
            result_data = last_tool_result["content"]
            parsed_result = result_data.is_a?(Hash) ? result_data : JSON.parse(result_data)
            # Return formatted recommendation
            format_recommendation(parsed_result)
          rescue JSON::ParserError
            # If parsing fails, return as string
            result_data.to_s
          end
        else
          # Fallback: return last message content
          last_msg = @messages.reverse.find { |m| %w[assistant user].include?(m["role"]) }
          return last_msg["content"] if last_msg && last_msg["content"]

          "Options agent completed but no result available"
        end
      end

      private

      def default_registry
        registry = Tools::Registry.new
        # Register Options tools (will be moved to Tools::Options namespace)
        registry.register(Tools::RecommendTrade)
        registry.register(Tools::FetchOptionChain)
        registry.register(Tools::AnalyzeTrend)
        registry.register(Tools::AnalyzeStructure15m)
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
        # Step 1: find_instrument
        return "find_instrument" unless @tools_called.include?("find_instrument")

        # Step 2: First fetch_intraday_history (15m)
        fetch_count = @tools_called.count("fetch_intraday_history")
        return "fetch_intraday_history" if fetch_count == 0

        # Step 2A: analyze_structure_15m
        return "analyze_structure_15m" unless @tools_called.include?("analyze_structure_15m")

        # After analyze_structure_15m, check if structure is valid
        structure_result = @messages.reverse.find do |m|
          next unless m["role"] == "tool"

          begin
            data = JSON.parse(m["content"])
            data["structure"] # This is likely analyze_structure_15m result
          rescue JSON::ParserError
            false
          end
        end

        if structure_result
          begin
            result = JSON.parse(structure_result["content"])
            if (result["structure"] == "range" || result["valid"] == false) && !@tools_called.include?("recommend_trade")
              # Structure is range/invalid - stop and go to recommend_trade
              return "recommend_trade"
            end
          rescue JSON::ParserError
            # Not JSON, continue
          end
        end

        # Step 3: Second fetch_intraday_history (5m) - only if structure is valid
        return "fetch_intraday_history" if fetch_count < 2

        # Step 4: analyze_trend
        return "analyze_trend" unless @tools_called.include?("analyze_trend")

        # Allow fetch_option_chain even with "avoid" trend - continue workflow normally
        # Previously skipped fetch_expiry_list and fetch_option_chain when trend was "avoid"
        # Now we allow the full workflow regardless of trend value
        return "fetch_expiry_list" unless @tools_called.include?("fetch_expiry_list")
        return "fetch_option_chain" unless @tools_called.include?("fetch_option_chain")
        return "recommend_trade" unless @tools_called.include?("recommend_trade")

        next_tool || "recommend_trade"
      end

      def format_recommendation(result)
        # Format the recommendation result for final output
        if result.is_a?(Hash)
          action = result["action"] || result[:action]

          if action == "NO_TRADE"
            reason = result["reason"] || result[:reason] || "No trade recommended"
            failed_gates = result["failed_gates"] || result[:failed_gates] || []
            expansion_score = result["expansion_score"] || result[:expansion_score]

            message = "NO_TRADE: #{reason}"
            message += "\nFailed gates: #{failed_gates.join(", ")}" if failed_gates.any?
            message += "\nExpansion score: #{expansion_score}/100" if expansion_score

            return message
          else
            # BUY recommendation
            side = result["side"] || result[:side]
            entry = result["entry_price"] || result[:entry_price]
            stop_loss = result["stop_loss_price"] || result[:stop_loss_price]
            target = result["target_price"] || result[:target_price]
            quantity = result["quantity"] || result[:quantity]
            lot_size = result["lot_size"] || result[:lot_size]
            score = result["expansion_score"] || result[:expansion_score]
            expected_premium = result["expected_premium"] || result[:expected_premium]

            message = "BUY #{side} - Entry: ₹#{entry.round(2)}, SL: ₹#{stop_loss.round(2)}, Target: ₹#{target.round(2)}"
            message += "\nQuantity: #{quantity} shares (#{lot_size} lots)"
            message += "\nExpansion Score: #{score}/100" if score
            message += "\nExpected Premium Move: ₹#{expected_premium.round(2)}" if expected_premium

            return message
          end
        end

        result.to_s
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
          base = "CRITICAL: You MUST call the analyze_trend tool NOW. DO NOT write any text, code, or explanations. ONLY call the tool. Parameters are automatically injected from context - call with empty parameters: {}. The candles array is already available in context from fetch_intraday_history."

          if last_result
            begin
              hist_data = JSON.parse(last_result["content"])
              if hist_data["candles"] && !hist_data["candles"].empty?
                base += " The candles array has #{hist_data["candles"].length} candles. Just call analyze_trend with empty parameters: {}."
              else
                base += " Even if candles are empty, you MUST still call analyze_trend with empty parameters: {}. It will return 'avoid' trend."
              end
            rescue JSON::ParserError
              base += " Call analyze_trend with empty parameters: {}. All data is auto-injected."
            end
          else
            base += " Call analyze_trend with empty parameters: {}. All data is auto-injected from context."
          end
        when "fetch_option_chain"
          # Extract symbol from find_instrument and trend from analyze_trend
          symbol_value = nil

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
          elsif trend_value == "avoid"
            base = "DO NOT call fetch_option_chain when trend is 'avoid'. Instead, call recommend_trade with trend='avoid' to get NO_TRADE recommendation."
          else
            base += " Use symbol from find_instrument result (the 'instrument' field - NOT empty string), trend from analyze_trend result (the 'trend' field - must be 'bullish' or 'bearish', NOT 'avoid'), and expiry='' (empty string for auto-selection). DO NOT pass exchange_segment, instrument, security_id, candles, interval, or strike_price."
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
          # Inject from context - but allow interval to be specified by LLM for 15m vs 5m
          raise "Missing instrument context" unless @context[:instrument]

          interval = args["interval"] || args[:interval] || "5" # Default to 5m, but allow LLM to specify 15m
          {
            "security_id" => @context[:instrument]["security_id"] || @context[:instrument][:security_id],
            "exchange_segment" => @context[:instrument]["exchange_segment"] || @context[:instrument][:exchange_segment],
            "instrument" => @context[:instrument]["instrument"] || @context[:instrument][:instrument],
            "interval" => interval.to_s
          }

        when "analyze_structure_15m"
          # Inject 15m candles from context - LLM params are ignored
          unless @context[:candles_15m]
            raise "Missing candles_15m context. You must call fetch_intraday_history with interval='15' first to fetch 15-minute candles."
          end

          { "candles" => @context[:candles_15m] }

        when "analyze_trend"
          # Inject candles from context - LLM params are ignored
          raise "Missing candles context" unless @context[:candles]

          { "candles" => @context[:candles] }

        when "fetch_expiry_list"
          # Inject underlying_seg and underlying_scrip from context
          raise "Missing instrument context" unless @context[:instrument]

          inst = @context[:instrument]
          original_seg = inst["exchange_segment"] || inst[:exchange_segment] || "IDX_I"
          original_scrip = inst["security_id"] || inst[:security_id]
          # Use stored symbol (original user input like "NIFTY" or "RELIANCE")
          symbol = inst["symbol"] || inst[:symbol] || inst["instrument"] || inst[:instrument]

          # Convert equity segment to FNO segment for stocks
          # For indices (IDX_I), keep as is
          # For stocks (NSE_EQ -> NSE_FNO, BSE_EQ -> BSE_FNO)
          underlying_seg = case original_seg.to_s
                           when "NSE_EQ"
                             "NSE_FNO"
                           when "BSE_EQ"
                             "BSE_FNO"
                           when "IDX_I"
                             "IDX_I"
                           else
                             original_seg # Keep as is for other segments
                           end

          # For stocks, we need to find the FNO instrument to get the correct security_id
          # For indices, use the same security_id
          if %w[NSE_FNO BSE_FNO].include?(underlying_seg)
            begin
              # Find the FNO instrument using the same symbol
              fno_inst = DhanHQ::Models::Instrument.find(underlying_seg, symbol.to_s.upcase)
              if fno_inst
                underlying_scrip = fno_inst.security_id.to_i
                @logger.info "Found FNO instrument for expiry list: #{symbol} -> #{underlying_seg}:#{underlying_scrip}"
              else
                # Fallback: try to use original security_id (may not work, but worth trying)
                @logger.warn "FNO instrument not found for #{symbol}, using original security_id: #{original_scrip}"
                underlying_scrip = original_scrip.to_i if original_scrip
              end
            rescue StandardError => e
              @logger.warn "Error finding FNO instrument for #{symbol}: #{e.message}, using original security_id"
              underlying_scrip = original_scrip.to_i if original_scrip
            end
          elsif original_scrip
            # For indices, use the same security_id
            underlying_scrip = original_scrip.to_i
          end

          # Provide both underlying_scrip (for OptionChain.fetch_expiry_list) and symbol (for fallback)
          args = {
            "underlying_seg" => underlying_seg
          }
          args["underlying_scrip"] = underlying_scrip if underlying_scrip
          args["symbol"] = symbol if symbol

          raise "Missing both security_id and symbol in instrument context" unless underlying_scrip || symbol

          args

        when "fetch_option_chain"
          # Inject all from context - LLM params are ignored
          raise "Missing instrument context" unless @context[:instrument]
          raise "Missing trend context" unless @context[:trend]
          raise "Missing expiry context" unless @context[:expiry]

          inst = @context[:instrument]
          original_seg = inst["exchange_segment"] || inst[:exchange_segment] || "IDX_I"
          original_scrip = inst["security_id"] || inst[:security_id]
          # Use stored symbol (original user input like "NIFTY" or "RELIANCE")
          symbol = inst["symbol"] || inst[:symbol] || inst["instrument"] || inst[:instrument]

          raise "Missing security_id in instrument context" unless original_scrip

          # Convert equity segment to FNO segment for stocks
          # For indices (IDX_I), keep as is
          # For stocks (NSE_EQ -> NSE_FNO, BSE_EQ -> BSE_FNO)
          underlying_seg = case original_seg.to_s
                           when "NSE_EQ"
                             "NSE_FNO"
                           when "BSE_EQ"
                             "BSE_FNO"
                           when "IDX_I"
                             "IDX_I"
                           else
                             original_seg # Keep as is for other segments
                           end

          # For stocks, we need to find the FNO instrument to get the correct security_id
          # For indices, use the same security_id
          if %w[NSE_FNO BSE_FNO].include?(underlying_seg)
            begin
              # Find the FNO instrument using the same symbol
              fno_inst = DhanHQ::Models::Instrument.find(underlying_seg, symbol.to_s.upcase)
              if fno_inst
                underlying_scrip = fno_inst.security_id.to_i
                @logger.info "Found FNO instrument: #{symbol} -> #{underlying_seg}:#{underlying_scrip}"
              else
                # Fallback: try to use original security_id (may not work, but worth trying)
                @logger.warn "FNO instrument not found for #{symbol}, using original security_id: #{original_scrip}"
                underlying_scrip = original_scrip.to_i
              end
            rescue StandardError => e
              @logger.warn "Error finding FNO instrument for #{symbol}: #{e.message}, using original security_id"
              underlying_scrip = original_scrip.to_i
            end
          else
            # For indices, use the same security_id
            underlying_scrip = original_scrip.to_i
          end

          {
            "underlying_seg" => underlying_seg,
            "underlying_scrip" => underlying_scrip,
            "symbol" => symbol, # Keep for fallback
            "expiry" => @context[:expiry],
            "trend" => @context[:trend]
          }

        when "recommend_trade"
          # Inject all from context - LLM params are ignored
          raise "Missing trend context" unless @context[:trend]

          args = {
            "trend" => @context[:trend]
          }

          # Add candles_5m and candles_15m for pre-trade gates
          args["candles_5m"] = @context[:candles] if @context[:candles]
          args["candles_15m"] = @context[:candles_15m] if @context[:candles_15m]

          # If trend is "avoid", option_chain is not required
          trend_value = @context[:trend].to_s.downcase
          if %w[avoid choppy].include?(trend_value)
            args["options"] = nil
          else
            raise "Missing option_chain context" unless @context[:option_chain]

            args["options"] = @context[:option_chain]
          end

          args

        else
          args
        end
      end

      def check_prerequisites(tool_name)
        required = TOOL_PREREQUISITES[tool_name] || []
        return if required.empty?

        # Special handling for recommend_trade - option_chain not required if trend is "avoid"
        if tool_name == "recommend_trade" && required.include?(:option_chain)
          trend_value = @context[:trend].to_s.downcase
          if %w[avoid choppy].include?(trend_value)
            # Remove option_chain from required when trend is avoid
            required = required.reject { |k| k == :option_chain }
          end
        end

        # Check if context keys are present (not nil)
        # In plain Ruby, we check for truthiness (nil and false are falsy)
        missing = required.reject { |k| @context[k] }
        return if missing.empty?

        missing_keys = missing.join(", ")
        raise "Tool #{tool_name} called without required context: #{missing_keys}. Call prerequisite tools first."
      end

      def store_in_context(tool_name, result, resolved_args = {})
        case tool_name
        when "find_instrument"
          @context[:instrument] = result.is_a?(Hash) ? result : JSON.parse(result)

        when "fetch_intraday_history"
          data = result.is_a?(Hash) ? result : JSON.parse(result)
          candles = data["candles"] || data[:candles] || data
          # Store based on interval: "15" -> candles_15m, "5" -> candles and candles_5m
          interval = resolved_args["interval"] || resolved_args[:interval] || "5"
          if interval.to_s == "15"
            @context[:candles_15m] = candles
          else
            @context[:candles] = candles
            @context[:candles_5m] = candles # Also store as candles_5m for clarity
          end

        when "analyze_structure_15m"
          data = result.is_a?(Hash) ? result : JSON.parse(result)
          @context[:structure_15m] = data

          # If structure is "range" (invalid), set trend to "avoid" to skip further analysis
          @context[:trend] = "avoid" if data["structure"] == "range" || data["valid"] == false

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
end
