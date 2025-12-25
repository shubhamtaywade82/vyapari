# frozen_string_literal: true

require "json"

module Vyapari
  module Swing
    # Swing trading agent - handles portfolio review and candidate scanning
    class Agent
      MAX_STEPS = 50 # Allow LLM to decide when workflow is complete (no strict limit)

      def initialize(client: Client.new, registry: default_registry, logger: nil)
        @client = client
        @registry = registry
        @messages = []
        @logger = logger || default_logger
        @step = 0
        @tools_called = []
        @context = {
          universe: [],
          candidates: [],
          portfolio: [],
          swing_history: {} # Store history by symbol: { "RELIANCE" => { "1h" => [...], "1d" => [...] } }
        }
      end

      def run(query)
        system_message = {
          role: "system",
          content: system_prompt
        }

        @messages << system_message
        @messages << { role: "user", content: query }
        @logger.info "🚀 Starting swing agent with query: #{query}"

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
            content = msg["content"].to_s.strip

            # Check if basic workflow steps are done
            basic_steps_done = @tools_called.include?("fetch_universe") &&
                              @tools_called.include?("filter_universe") &&
                              @tools_called.include?("batch_analyze_universe")

            # If basic steps done but recommend_swing_trades not called, suggest it (but don't force)
            if basic_steps_done && !@tools_called.include?("recommend_swing_trades")
              # Check if we have candidates to recommend
              if @context[:top_candidates] && @context[:top_candidates].any?
                @logger.info "ℹ️  Candidates available (#{@context[:top_candidates].size}). LLM can call recommend_swing_trades or return final response."
                # Don't force - let LLM decide
              end
            end

            # If basic steps not done, guide to next step (but don't force)
            unless basic_steps_done
              next_tool = determine_next_tool
              if next_tool
                @logger.info "ℹ️  Suggested next step: #{next_tool}. Called: #{@tools_called.join(", ")}"
                @messages << {
                  role: "user",
                  content: "Suggested next step: Call #{next_tool} tool. You can also return final response if workflow is complete."
                }
                next
              end
            end

            # Validate response is proper JSON (not a tool call structure)
            if content.match?(/^\s*\{.*"name".*"parameters".*\}\s*$/) || content.match?(/^\s*\{.*"name".*"message".*\}\s*$/)
              @logger.warn "⚠️  LLM returned tool-call-like structure instead of JSON. Using context data instead."
              return finalize(nil) # Use context data
            end

            # LLM decided to return final response - allow it
            @logger.info "✅ Swing agent completed. LLM decided workflow is complete. Final response: #{content}"
            return finalize(content)
          end

          tool_calls = msg["tool_calls"]

          # Process tools sequentially
          if tool_calls.length > 1
            @logger.warn "⚠️  LLM tried to call #{tool_calls.length} tools in parallel. Only processing the first one."
            tool_calls = [tool_calls.first]
          end

          @logger.info "🔧 LLM selected #{tool_calls.length} tool(s): #{tool_calls.map { |tc| tc["function"]["name"] }.join(", ")}"

          tool_calls.each do |call|
            tool_name = call["function"]["name"]
            arguments = call["function"]["arguments"]
            parsed_args = arguments.is_a?(String) ? JSON.parse(arguments) : arguments

            # Resolve arguments from context (auto-inject universe, etc.)
            resolved_args = resolve_arguments(tool_name, parsed_args)

            @logger.info "\n  🛠️  Tool: #{tool_name}"
            @logger.info "     Parameters: #{parsed_args.inspect}"
            @logger.info "     Resolved Parameters: #{resolved_args.inspect}"

            begin
              tool_class = @registry.fetch(tool_name)
              tool = tool_class.new
              result = tool.call(resolved_args)
              store_in_context(tool_name, result)

              result_summary = result.is_a?(Hash) ? result.keys.join(", ") : result.to_s[0..100]
              @logger.info "     ✅ Result: #{result_summary}"

              @tools_called << tool_name

              @messages << {
                role: "tool",
                tool_call_id: call["id"],
                content: result.is_a?(String) ? result : result.to_json
              }

              # Check if workflow is complete after this tool
              # For now, allow agent to continue after filtering to analyze stocks
              # Workflow completion will be determined by LLM or max steps
            rescue StandardError => e
              @logger.error "     ❌ Error: #{e.message}"
              raise
            end
          end

          @logger.info "     🔄 Waiting for LLM to decide next action..."
        end

        # If we hit max steps, return what we have (LLM may have decided to stop earlier)
        @logger.warn "⚠️  Reached MAX_STEPS (#{MAX_STEPS}). Returning current state."
        return finalize(nil)
      end

      private

      def system_prompt
        <<~PROMPT
          You are a swing trading analysis agent.

          RULES:
          - You analyze EQUITY stocks only (NSE_EQ).
          - You MUST NOT place trades.
          - You MUST ONLY respond with tool calls until the task is complete.
          - You MUST NOT provide text explanations - only call tools.
          - Final response MUST be valid JSON.

          AVAILABLE TOOLS:
          - fetch_universe: Fetches the swing trading universe (list of stock symbols) from NSE indices.
          - filter_universe: Filters the universe to a smaller, manageable list (recommended: 20-50 stocks). The universe parameter is automatically injected from context.
          - batch_analyze_universe: Efficiently analyzes ALL stocks in the filtered universe (Ruby does the work). Returns top scored candidates. The universe parameter is automatically injected from context.
          - recommend_swing_trades: Provides swing trading recommendations (entry, SL, TP, HOLD) for top candidates. The candidates parameter is automatically injected from batch_analyze_universe result.

          WORKFLOW (EFFICIENT - Ruby processes, LLM recommends):
          STEP 1: Call fetch_universe tool with empty parameters {}.
          STEP 2: Call filter_universe tool with limit=50 and strategy="top_large_cap". The universe parameter is automatically injected.
          STEP 3: Call batch_analyze_universe tool with limit=20. This tool processes ALL stocks in Ruby (efficient), calculates technicals, scores each stock, and returns top candidates. The universe parameter is automatically injected.
          STEP 4: Call recommend_swing_trades tool. The candidates parameter is automatically injected from batch_analyze_universe result.
          STEP 5: After recommend_swing_trades, return final JSON with swing trading recommendations (entry, SL, TP, holding period) for each top candidate.

          CRITICAL RULES:
          - DO NOT call fetch_swing_history or analyze_swing_technicals individually - use batch_analyze_universe instead
          - batch_analyze_universe processes ALL stocks efficiently in Ruby (not LLM)
          - After batch_analyze_universe, you can either:
            a) Call recommend_swing_trades tool (candidates auto-injected), OR
            b) Return final JSON directly with recommendations
          - Provide swing trading recommendations: entry price, stop loss, target prices, holding period (5-15 days), and action (BUY/HOLD/AVOID)
          - You decide when workflow is complete - return final JSON when ready
          - DO NOT provide text explanations - only call tools until final response

          CRITICAL RULES:
          - You MUST call BOTH fetch_universe AND filter_universe before returning final response
          - After filter_universe completes, return JSON immediately - do NOT call more tools
          - DO NOT return structures like {"name": "message", "parameters": {...}} - that's a tool call format, not JSON
          - Return ONLY the JSON object directly, no wrapper, no tool call structure
          - The universe data will be automatically included from context

          You MUST call tools ONE AT A TIME, sequentially.
        PROMPT
      end

      def default_registry
        registry = Tools::Registry.new
        # Register Swing tools
        registry.register(Tools::Swing::FetchUniverse)
        registry.register(Tools::Swing::FilterUniverse)
        registry.register(Tools::Swing::BatchAnalyzeUniverse) # Efficient batch processing
        registry.register(Tools::Swing::RecommendSwingTrades) # LLM provides final recommendations
        # Individual tools (kept for backward compatibility, but batch_analyze_universe is preferred)
        # registry.register(Tools::Swing::FetchSwingHistory)
        # registry.register(Tools::Swing::AnalyzeSwingTechnicals)
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

      def resolve_arguments(tool_name, args)
        case tool_name
        when "fetch_universe"
          # LLM provides these, use as-is
          args

        when "filter_universe"
          # Auto-inject universe from context if available
          resolved = args.dup
          if @context[:universe] && @context[:universe].any?
            resolved["universe"] = @context[:universe]
            @logger.info "     🔄 Auto-injected universe from context (#{@context[:universe].size} symbols)"
          end
          # Set defaults if not provided
          resolved["limit"] ||= 50
          resolved["strategy"] ||= "top_large_cap"
          resolved

        when "fetch_swing_history"
          # LLM provides symbol, use as-is
          args

        when "analyze_swing_technicals"
          # Auto-inject candles from context if available
          resolved = args.dup
          symbol = (resolved["symbol"] || resolved[:symbol]).to_s.upcase

          if @context[:swing_history] && @context[:swing_history][symbol]
            history = @context[:swing_history][symbol]
            resolved["candles_1h"] ||= history["1h"] || history[:one_hour] || []
            resolved["candles_1d"] ||= history["1d"] || history[:one_day] || []
            @logger.info "     🔄 Auto-injected candles from context for #{symbol}"
          elsif @context[:swing_history] && @context[:swing_history].any?
            # Try to find from most recent fetch_swing_history result
            last_history_symbol = @context[:swing_history].keys.last
            if last_history_symbol
              history = @context[:swing_history][last_history_symbol]
              resolved["candles_1h"] ||= history["1h"] || history[:one_hour] || []
              resolved["candles_1d"] ||= history["1d"] || history[:one_day] || []
              @logger.info "     🔄 Auto-injected candles from most recent history (#{last_history_symbol})"
            end
          end
          resolved

        when "batch_analyze_universe"
          # Auto-inject universe from context if available
          resolved = args.dup
          if @context[:universe] && @context[:universe].any?
            resolved["universe"] = @context[:universe]
            @logger.info "     🔄 Auto-injected universe from context (#{@context[:universe].size} symbols)"
          end
          resolved["limit"] ||= 20
          resolved

        when "recommend_swing_trades"
          # Auto-inject candidates from context if available
          resolved = args.dup
          if @context[:top_candidates] && @context[:top_candidates].any?
            resolved["candidates"] = @context[:top_candidates]
            @logger.info "     🔄 Auto-injected #{@context[:top_candidates].size} candidates from context"
          else
            # If LLM passed empty object or string, try to get from context anyway
            candidates_param = resolved["candidates"] || resolved[:candidates]
            if candidates_param.nil? || candidates_param == {} || candidates_param == "{}" || (candidates_param.is_a?(String) && candidates_param.strip == "{}")
              resolved["candidates"] = @context[:top_candidates] || []
              @logger.info "     🔄 Auto-injected candidates from context (LLM passed empty: #{candidates_param.inspect})"
            end
          end
          resolved

        else
          args
        end
      end

      def store_in_context(tool_name, result)
        case tool_name
        when "fetch_universe"
          data = result.is_a?(Hash) ? result : JSON.parse(result)
          @context[:universe] = data["universe"] || data[:universe] || []
        when "filter_universe"
          data = result.is_a?(Hash) ? result : JSON.parse(result)
          # Update universe with filtered list
          @context[:universe] = data["filtered_universe"] || data[:filtered_universe] || []
        when "fetch_swing_history"
          data = result.is_a?(Hash) ? result : JSON.parse(result)
          symbol = (data["symbol"] || data[:symbol]).to_s.upcase
          @context[:swing_history][symbol] = {
            "1h" => data["1h"] || data[:one_hour] || [],
            "1d" => data["1d"] || data[:one_day] || []
          }
        when "batch_analyze_universe"
          data = result.is_a?(Hash) ? result : JSON.parse(result)
          # Store top candidates for recommend_swing_trades
          candidates = data["top_candidates"] || data[:top_candidates] || []
          @context[:top_candidates] = candidates
          @context[:all_analyzed] = data["all_analyzed"] || data[:all_analyzed] || []
          @logger.info "     📊 Stored #{candidates.size} top candidates for recommendation"
          # Log sample for debugging
          if candidates.any?
            sample = candidates.first
            @logger.info "     📈 Sample candidate: #{sample["symbol"]} (score: #{sample["score"]}, trend: #{sample["trend"]})"
          end
        when "recommend_swing_trades"
          # Store recommendations if provided
          data = result.is_a?(Hash) ? result : JSON.parse(result)
          @context[:recommendations] = data
          @logger.info "     📋 Stored swing trading recommendations"
        when "analyze_swing_technicals"
          data = result.is_a?(Hash) ? result : JSON.parse(result)
          symbol = (data["symbol"] || data[:symbol]).to_s.upcase
          # Store analysis in candidates
          @context[:candidates] ||= []
          @context[:candidates] << data
        when "fetch_portfolio"
          @context[:portfolio] = result.is_a?(Hash) ? result : JSON.parse(result)
        # Add more context storage as tools are added
        end
      end

      def finalize(content)
        # Build response from context (primary source of truth)
        response = {
          "mode" => "SWING",
          "universe" => @context[:universe] || [],
          "universe_count" => @context[:universe]&.size || 0,
          "top_candidates" => @context[:top_candidates] || [],
          "recommendations" => @context[:recommendations] || [],
          "portfolio_review" => @context[:portfolio] || [],
          "new_candidates" => @context[:candidates] || []
        }

        # Try to parse and merge content if provided and valid
        if content && !content.to_s.strip.empty?
          json_content = content.to_s.strip
          # Remove markdown code blocks if present
          json_content = json_content.gsub(/^```json\s*/, "").gsub(/^```\s*/, "").gsub(/\s*```$/, "").strip

          begin
            parsed = JSON.parse(json_content)
            # Merge parsed content, but prioritize context data
            response.merge!(parsed) do |_key, context_val, parsed_val|
              # Prefer context data over parsed data for critical fields
              context_val.is_a?(Array) && context_val.any? ? context_val : parsed_val
            end
          rescue JSON::ParserError
            # If JSON parsing fails, just use the message
            response["message"] = json_content unless json_content.empty?
          end
        end

        # Add status message if not present
        response["message"] ||= "Universe fetched and filtered successfully. Ready for further analysis."
        response["status"] = "complete"

        response
      end

      def determine_next_tool
        return "fetch_universe" unless @tools_called.include?("fetch_universe")
        return "filter_universe" unless @tools_called.include?("filter_universe")
        return "batch_analyze_universe" unless @tools_called.include?("batch_analyze_universe")
        return "recommend_swing_trades" unless @tools_called.include?("recommend_swing_trades")
        nil # Workflow complete
      end

      attr_reader :client, :registry, :messages, :logger, :step, :tools_called, :context
    end
  end
end

