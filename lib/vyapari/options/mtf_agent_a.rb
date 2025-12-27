# frozen_string_literal: true

# Multi-Timeframe Agent A for Vyapari options trading
# Fixed, ordered, top-down MTF pass (no backtracking)

require_relative "agent_prompts"
require_relative "strike_selection_framework"
require "json"

module Vyapari
  module Options
    # Agent A with multi-timeframe analysis
    # Performs FIXED, ORDERED, TOP-DOWN MTF PASS
    class MTFAgentA
      # Analysis modes
      MODES = {
        options_intraday: "OPTIONS_INTRADAY",
        swing_trading: "SWING_TRADING"
      }.freeze

      # Timeframe configurations per mode
      TIMEFRAME_CONFIGS = {
        options_intraday: {
          htf: { timeframe: "15m", purpose: "Structure & Regime" },
          mtf: { timeframe: "5m", purpose: "Direction & Momentum" },
          ltf: { timeframe: "1m", purpose: "Entry Trigger" }
        },
        swing_trading: {
          htf: { timeframe: "1D", purpose: "Primary Trend" },
          mtf: { timeframe: "1H", purpose: "Setup Formation" },
          ltf: { timeframe: "15m", purpose: "Entry Zone" }
        }
      }.freeze

      # Iteration budget per timeframe
      ITERATION_BUDGET = {
        options_intraday: {
          htf_analysis: 2,
          mtf_analysis: 2,
          ltf_trigger: 2,
          strike_selection: 2,
          synthesis: 1,
          total: 9
        },
        swing_trading: {
          htf_analysis: 2,
          mtf_analysis: 2,
          ltf_trigger: 2,
          synthesis: 1,
          total: 7
        }
      }.freeze

      def initialize(client: nil, registry: nil, mode: :options_intraday)
        @client = client || create_ollama_client
        @registry = registry
        @mode = mode
        @timeframe_config = TIMEFRAME_CONFIGS[@mode] || TIMEFRAME_CONFIGS[:options_intraday]
        @iteration_budget = ITERATION_BUDGET[@mode] || ITERATION_BUDGET[:options_intraday]
      end

      # Run complete MTF analysis
      # @param task [String] Initial task
      # @return [Hash] Complete MTF analysis result
      def run(task)
        result = {
          mode: @mode,
          timeframes: {},
          trade_plan: nil,
          status: nil,
          iterations_used: 0
        }

        # PHASE 1: Higher Timeframe Analysis
        htf_result = analyze_htf(task)
        result[:timeframes][:htf] = htf_result
        result[:iterations_used] += (htf_result[:iterations] || 0)

        # Early exit if HTF says NO_TRADE
        if htf_result[:tradable] == false || htf_result[:regime] == "NO_TRADE"
          result[:status] = "no_trade"
          result[:reason] = "Higher timeframe indicates NO_TRADE: #{htf_result[:reason]}"
          return result
        end

        # PHASE 2: Mid Timeframe Analysis
        mtf_result = analyze_mtf(htf_result, task)
        result[:timeframes][:mtf] = mtf_result
        result[:iterations_used] += (mtf_result[:iterations] || 0)

        # Check alignment with HTF
        unless aligned_with_htf?(htf_result, mtf_result)
          result[:status] = "no_trade"
          result[:reason] = "Mid timeframe does not align with higher timeframe"
          return result
        end

        # PHASE 3: Lower Timeframe Trigger
        ltf_result = analyze_ltf(mtf_result, task)
        result[:timeframes][:ltf] = ltf_result
        result[:iterations_used] += (ltf_result[:iterations] || 0)

        # PHASE 4: Strike Selection (OPTIONS MODE ONLY)
        if @mode == :options_intraday
          strike_result = analyze_strike_selection(htf_result, mtf_result, ltf_result, task)
          result[:timeframes][:strike_selection] = strike_result
          result[:iterations_used] += (strike_result[:iterations] || 0)

          # Early exit if no valid strikes
          if strike_result[:candidates].empty?
            result[:status] = "no_trade"
            result[:reason] = "No valid strike candidates found: #{strike_result[:reason]}"
            return result
          end
        else
          # Swing trading doesn't need strike selection
          strike_result = nil
        end

        # PHASE 5: Final Synthesis
        synthesis_result = synthesize_trade_plan(htf_result, mtf_result, ltf_result, strike_result)
        result[:iterations_used] += (synthesis_result[:iterations] || 0)
        result[:trade_plan] = synthesis_result[:trade_plan]
        result[:status] = synthesis_result[:status]

        result
      end

      private

      # Analyze Higher Timeframe
      def analyze_htf(task)
        config = @timeframe_config[:htf]
        prompt = build_htf_prompt(config, task)

        agent = create_agent(max_iterations: @iteration_budget[:htf_analysis])
        result = agent.loop(task: prompt)

        extract_htf_result(result, config)
      end

      # Analyze Mid Timeframe
      def analyze_mtf(htf_result, task)
        config = @timeframe_config[:mtf]
        prompt = build_mtf_prompt(config, htf_result, task)

        agent = create_agent(max_iterations: @iteration_budget[:mtf_analysis] || 2)
        result = agent.loop(task: prompt)

        extract_mtf_result(result, config)
      end

      # Analyze Lower Timeframe
      def analyze_ltf(mtf_result, task)
        config = @timeframe_config[:ltf]
        prompt = build_ltf_prompt(config, mtf_result, task)

        agent = create_agent(max_iterations: @iteration_budget[:ltf_trigger] || 2)
        result = agent.loop(task: prompt)

        extract_ltf_result(result, config)
      end

      # Analyze strike selection (OPTIONS MODE ONLY)
      def analyze_strike_selection(htf_result, mtf_result, ltf_result, task)
        prompt = build_strike_selection_prompt(htf_result, mtf_result, ltf_result, task)

        agent = create_agent(max_iterations: @iteration_budget[:strike_selection] || 2)
        result = agent.loop(task: prompt)

        {
          candidates: extract_strike_candidates(result),
          atm_strike: extract_atm_strike(result),
          reason: extract_strike_reason(result),
          iterations: result[:iterations]
        }
      end

      # Synthesize final trade plan
      def synthesize_trade_plan(htf_result, mtf_result, ltf_result, strike_result = nil)
        prompt = build_synthesis_prompt(htf_result, mtf_result, ltf_result, strike_result)

        agent = create_agent(max_iterations: @iteration_budget[:synthesis] || 1)
        result = agent.loop(task: prompt)

        {
          trade_plan: extract_trade_plan(result),
          status: result[:status] == "completed" ? "completed" : "failed",
          iterations: result[:iterations] || 0
        }
      end

      # Build HTF prompt
      def build_htf_prompt(config, task)
        if @mode == :options_intraday
          build_options_htf_prompt(config, task)
        else
          build_swing_htf_prompt(config, task)
        end
      end

      # Build Options HTF (15m) prompt
      def build_options_htf_prompt(config, task)
        <<~PROMPT
          You are analyzing the HIGHER TIMEFRAME (#{config[:timeframe]}) for options trading.

          CRITICAL RULE: This is the FIRST and MOST IMPORTANT decision.
          If this timeframe says NO_TRADE, the entire analysis stops.

          QUESTION: Is this a tradable market?

          You must decide ONE and ONLY ONE:
          - TREND_DAY (strong directional move)
          - RANGE / CHOP (sideways, avoid)
          - VOLATILITY_EXPANSION (expanding range, tradable)
          - NO_TRADE (unclear, choppy, avoid)

          INPUTS TO USE:
          - 15m OHLC candles
          - VWAP
          - Range expansion indicators
          - Previous day high/low

          OUTPUT SCHEMA:
          {
            "timeframe": "15m",
            "regime": "TREND_DAY | RANGE | VOLATILITY_EXPANSION | NO_TRADE",
            "tradable": true | false,
            "reason": "explanation",
            "structure": "HH_HL | LH_LL | RANGE"
          }

          RULES:
          1. Fetch 15m historical data using dhan.history.intraday
          2. Analyze structure and regime
          3. If unclear or choppy → return NO_TRADE
          4. Maximum #{@iteration_budget[:htf_analysis]} iterations
          5. Output final decision (action: "final")

          TASK: #{task}

          REMEMBER: If you return NO_TRADE here, lower timeframes will NOT be analyzed.
        PROMPT
      end

      # Build Swing HTF (1D) prompt
      def build_swing_htf_prompt(config, task)
        <<~PROMPT
          You are analyzing the HIGHER TIMEFRAME (#{config[:timeframe]}) for swing trading.

          CRITICAL RULE: This is the FIRST and MOST IMPORTANT decision.
          If this timeframe says SIDEWAYS, the entire analysis stops.

          QUESTION: Is this stock worth holding for days/weeks?

          You must decide:
          - Trend: UP / DOWN / SIDEWAYS
          - Structure: HH-HL (bullish) / LH-LL (bearish) / RANGE
          - Location: Near support / resistance / breakout

          OUTPUT SCHEMA:
          {
            "timeframe": "1D",
            "trend": "UP | DOWN | SIDEWAYS",
            "structure": "HH_HL | LH_LL | RANGE",
            "tradable": true | false,
            "reason": "explanation",
            "location": "support | resistance | breakout"
          }

          RULES:
          1. Fetch daily historical data using dhan.history.daily
          2. Analyze primary trend and structure
          3. If trend = SIDEWAYS → return tradable: false
          4. Maximum #{@iteration_budget[:htf_analysis]} iterations
          5. Output final decision (action: "final")

          TASK: #{task}
        PROMPT
      end

      # Build MTF prompt
      def build_mtf_prompt(config, htf_result, task)
        if @mode == :options_intraday
          build_options_mtf_prompt(config, htf_result, task)
        else
          build_swing_mtf_prompt(config, htf_result, task)
        end
      end

      # Build Options MTF (5m) prompt
      def build_options_mtf_prompt(config, htf_result, task)
        <<~PROMPT
          You are analyzing the MID TIMEFRAME (#{config[:timeframe]}) for options trading.

          CRITICAL RULE: Your direction MUST agree with the higher timeframe (15m).
          If it doesn't → return NO_TRADE.

          HIGHER TIMEFRAME CONTEXT:
          #{JSON.pretty_generate(htf_result)}

          QUESTION: Which side has control?

          You must determine:
          - Direction: BULLISH / BEARISH / NEUTRAL
          - Momentum: STRONG / WEAK
          - Context: PULLBACK / BREAKOUT

          HARD RULE: 5m direction must AGREE with 15m regime.
          If 15m = TREND_DAY and 5m = NEUTRAL → NO_TRADE
          If 15m = BULLISH and 5m = BEARISH → NO_TRADE

          OUTPUT SCHEMA:
          {
            "timeframe": "5m",
            "direction": "BULLISH | BEARISH | NEUTRAL",
            "momentum": "STRONG | WEAK",
            "context": "PULLBACK | BREAKOUT",
            "aligned_with_htf": true | false,
            "reason": "explanation"
          }

          RULES:
          1. Fetch 5m historical data using dhan.history.intraday
          2. Check alignment with 15m regime
          3. If not aligned → return aligned_with_htf: false
          4. Maximum #{@iteration_budget[:mtf_analysis]} iterations
          5. Output final decision (action: "final")

          TASK: #{task}
        PROMPT
      end

      # Build Swing MTF (1H) prompt
      def build_swing_mtf_prompt(config, htf_result, task)
        <<~PROMPT
          You are analyzing the MID TIMEFRAME (#{config[:timeframe]}) for swing trading.

          CRITICAL RULE: Your setup MUST align with the daily trend.
          If no clean setup → return NO_TRADE.

          HIGHER TIMEFRAME CONTEXT:
          #{JSON.pretty_generate(htf_result)}

          QUESTION: Is a setup forming inside the trend?

          Look for:
          - Pullback to support/resistance
          - Base formation
          - Compression
          - Breakout structure

          OUTPUT SCHEMA:
          {
            "timeframe": "1H",
            "setup": "PULLBACK | BREAKOUT | BASE | NONE",
            "aligned_with_htf": true | false,
            "reason": "explanation"
          }

          RULES:
          1. Fetch 1H historical data using dhan.history.intraday
          2. Check alignment with daily trend
          3. If no clean setup → return setup: NONE
          4. Maximum #{@iteration_budget[:mtf_analysis]} iterations
          5. Output final decision (action: "final")

          TASK: #{task}
        PROMPT
      end

      # Build LTF prompt
      def build_ltf_prompt(config, mtf_result, task)
        if @mode == :options_intraday
          build_options_ltf_prompt(config, mtf_result, task)
        else
          build_swing_ltf_prompt(config, mtf_result, task)
        end
      end

      # Build Options LTF (1m) prompt
      def build_options_ltf_prompt(config, mtf_result, task)
        <<~PROMPT
          You are analyzing the LOWER TIMEFRAME (#{config[:timeframe]}) for options trading.

          CRITICAL RULES:
          1. 1m is ONLY for entry trigger - it CANNOT change bias
          2. 1m CANNOT override higher timeframes
          3. Use 1m ONLY for entry candle and SL placement

          MID TIMEFRAME CONTEXT:
          #{JSON.pretty_generate(mtf_result)}

          QUESTION: Where exactly do we enter?

          Determine:
          - Entry type: BREAKOUT / PULLBACK
          - Entry trigger: specific price/level
          - SL placement: invalidation level

          OUTPUT SCHEMA:
          {
            "timeframe": "1m",
            "entry_type": "BREAKOUT | PULLBACK",
            "trigger": "description of entry",
            "sl_level": "number",
            "reason": "explanation"
          }

          RULES:
          1. Fetch 1m historical data using dhan.history.intraday
          2. Find entry trigger that aligns with 5m direction
          3. Define SL level (invalidation)
          4. Maximum #{@iteration_budget[:ltf_trigger]} iterations
          5. Output final decision (action: "final")

          TASK: #{task}

          REMEMBER: 1m refines price only, never changes bias from higher TFs.
        PROMPT
      end

      # Build Swing LTF (15m) prompt
      def build_swing_ltf_prompt(config, mtf_result, task)
        <<~PROMPT
          You are analyzing the LOWER TIMEFRAME (#{config[:timeframe]}) for swing trading.

          CRITICAL RULES:
          1. 15m is ONLY for entry zone - it CANNOT change bias
          2. 15m CANNOT override higher timeframes
          3. Use 15m ONLY for entry zone and initial SL

          MID TIMEFRAME CONTEXT:
          #{JSON.pretty_generate(mtf_result)}

          QUESTION: Where exactly do we enter with defined risk?

          Determine:
          - Entry zone: price range
          - Initial SL: invalidation level
          - Risk context: swing low/high

          OUTPUT SCHEMA:
          {
            "timeframe": "15m",
            "entry_zone": "description",
            "sl_level": "number",
            "swing_low": "number (if bullish)",
            "swing_high": "number (if bearish)",
            "reason": "explanation"
          }

          RULES:
          1. Fetch 15m historical data using dhan.history.intraday
          2. Find entry zone that aligns with 1H setup
          3. Define initial SL (invalidation)
          4. Maximum #{@iteration_budget[:ltf_trigger]} iterations
          5. Output final decision (action: "final")

          TASK: #{task}

          REMEMBER: 15m refines entry only, never changes bias from higher TFs.
        PROMPT
      end

      # Build strike selection prompt
      def build_strike_selection_prompt(htf_result, mtf_result, ltf_result, task)
        <<~PROMPT
          You are performing STRIKE SELECTION for options trading.

          CRITICAL: Strike selection is a FUNCTION of MOMENTUM + VOLATILITY + TIME LEFT,
          NOT "nearest ATM" or "cheap premium".

          CONTEXT FROM TIMEFRAME ANALYSIS:
          Higher TF (15m): #{JSON.pretty_generate(htf_result)}
          Mid TF (5m): #{JSON.pretty_generate(mtf_result)}
          Lower TF (1m): #{JSON.pretty_generate(ltf_result)}

          DECISION FRAMEWORK (ANSWER IN ORDER):

          1. Direction → CE or PE
             - From MTF analysis: #{mtf_result[:direction]}
             - Decision: #{mtf_result[:direction] == "BULLISH" ? "CE" : "PE"}

          2. Market Regime → How FAR OTM?
             - 15m Regime: #{htf_result[:regime]}
             - Strong Trend/Expansion → ATM to 1 step OTM
             - Normal Trend → ATM only
             - Range/Chop → NO_TRADE (already filtered)

          3. Momentum Strength → ITM vs ATM vs OTM
             - 5m Momentum: #{mtf_result[:momentum]}
             - STRONG → ATM or slight OTM
             - MODERATE → ATM only
             - WEAK → NO_TRADE (already filtered)

          4. Volatility Filter (MANDATORY)
             - Check VIX/IV or 15m candle expansion
             - Vol expanding → Allow OTM
             - Vol average → ATM only
             - Vol contracting → NO_TRADE

          5. Time Remaining (Intraday Reality)
             - Current time: #{Time.now.strftime("%H:%M")}
             - 9:20-11:30 → ATM/1 OTM
             - 11:30-13:30 → ATM only
             - 13:30-14:45 → ITM/ATM
             - After 14:45 → NO NEW TRADES

          TOOLS TO USE:
          - dhan.option.chain (get option chain with strikes, premiums, Greeks)
          - dhan.market.ltp (get current spot price)

          OUTPUT SCHEMA:
          {
            "preferred_type": "CE | PE",
            "atm_strike": 22500,
            "candidates": [
              {
                "security_id": "string",
                "strike": 22500,
                "type": "CE | PE",
                "moneyness": "ATM | ITM | OTM",
                "reason": "explanation",
                "risk_note": "note about risk"
              }
            ]
          }

          RULES:
          1. Fetch option chain for ±1-2 strikes around ATM ONLY
          2. Do NOT scan entire chain (creates noise)
          3. Extract: strike, LTP, delta (if available), IV (if available), bid-ask spread
          4. Apply all 5 filters above
          5. Maximum #{@iteration_budget[:strike_selection]} iterations
          6. Output final strike candidates (action: "final")

          TASK: #{task}

          REMEMBER: Strike selection is PART of analysis, but execution happens after Agent B validates.
        PROMPT
      end

      # Build synthesis prompt
      def build_synthesis_prompt(htf_result, mtf_result, ltf_result, strike_result = nil)
        if @mode == :options_intraday
          build_options_synthesis_prompt(htf_result, mtf_result, ltf_result, strike_result)
        else
          build_swing_synthesis_prompt(htf_result, mtf_result, ltf_result)
        end
      end

      # Build Options synthesis prompt
      def build_options_synthesis_prompt(htf_result, mtf_result, ltf_result, strike_result = nil)
        prompt = <<~PROMPT
          Synthesize the multi-timeframe analysis + strike selection into a final TradePlan.

          HIGHER TIMEFRAME (15m):
          #{JSON.pretty_generate(htf_result)}

          MID TIMEFRAME (5m):
          #{JSON.pretty_generate(mtf_result)}

          LOWER TIMEFRAME (1m):
          #{JSON.pretty_generate(ltf_result)}
        PROMPT

        if strike_result
          prompt += <<~PROMPT

            STRIKE SELECTION:
            #{JSON.pretty_generate(strike_result)}
          PROMPT
        end

        prompt += <<~PROMPT

          OUTPUT SCHEMA (TradePlan):
          {
            "mode": "OPTIONS_INTRADAY",
            "htf": {
              "timeframe": "15m",
              "regime": "TREND_DAY | RANGE | VOLATILITY_EXPANSION",
              "tradable": true
            },
            "mtf": {
              "timeframe": "5m",
              "direction": "BULLISH | BEARISH",
              "momentum": "STRONG | WEAK"
            },
            "ltf": {
              "timeframe": "1m",
              "entry_type": "BREAKOUT | PULLBACK",
              "trigger": "description"
            },
            "bias": "BULLISH | BEARISH | NO_TRADE",
            "strike_bias": "CE | PE",
            "strike_selection": {
              "preferred_type": "CE | PE",
              "atm_strike": 22500,
              "candidates": [
                {
                  "security_id": "string",
                  "strike": 22500,
                  "type": "CE | PE",
                  "moneyness": "ATM | ITM | OTM",
                  "reason": "explanation",
                  "risk_note": "note about risk"
                }
              ]
            },
            "invalidations": ["condition1", "condition2"]
          }

          RULES:
          1. Combine all timeframe analyses + strike selection
          2. Determine final bias from MTF direction
          3. Set strike bias (CE for bullish, PE for bearish)
          4. Include strike_selection from strike analysis
          5. List invalidation conditions
          6. Maximum 1 iteration
          7. Output final TradePlan (action: "final")
        PROMPT

        prompt
      end

      # Build Swing synthesis prompt
      def build_swing_synthesis_prompt(htf_result, mtf_result, ltf_result)
        <<~PROMPT
          Synthesize the multi-timeframe analysis into a final TradePlan.

          HIGHER TIMEFRAME (1D):
          #{JSON.pretty_generate(htf_result)}

          MID TIMEFRAME (1H):
          #{JSON.pretty_generate(mtf_result)}

          LOWER TIMEFRAME (15m):
          #{JSON.pretty_generate(ltf_result)}

          OUTPUT SCHEMA (TradePlan):
          {
            "mode": "SWING_TRADING",
            "htf": {
              "timeframe": "1D",
              "trend": "UP | DOWN",
              "structure": "HH_HL | LH_LL"
            },
            "mtf": {
              "timeframe": "1H",
              "setup": "PULLBACK | BREAKOUT | BASE"
            },
            "ltf": {
              "timeframe": "15m",
              "entry_zone": "description"
            },
            "bias": "BULLISH | BEARISH | NO_TRADE",
            "risk_context": {
              "swing_low": 123.5,
              "invalid_below": 121.0
            }
          }

          RULES:
          1. Combine all three timeframe analyses
          2. Determine final bias from daily trend
          3. Set risk context from swing levels
          4. Maximum 1 iteration
          5. Output final TradePlan (action: "final")
        PROMPT
      end

      # Extract HTF result
      def extract_htf_result(agent_result, config)
        {
          timeframe: config[:timeframe],
          regime: extract_regime(agent_result),
          tradable: extract_tradable(agent_result),
          reason: agent_result[:reason],
          iterations: agent_result[:iterations] || 0
        }
      end

      # Extract MTF result
      def extract_mtf_result(agent_result, config)
        {
          timeframe: config[:timeframe],
          direction: extract_direction(agent_result),
          momentum: extract_momentum(agent_result),
          aligned_with_htf: extract_alignment(agent_result),
          reason: agent_result[:reason],
          iterations: agent_result[:iterations] || 0
        }
      end

      # Extract LTF result
      def extract_ltf_result(agent_result, config)
        {
          timeframe: config[:timeframe],
          entry_type: extract_entry_type(agent_result),
          trigger: extract_trigger(agent_result),
          sl_level: extract_sl_level(agent_result),
          reason: agent_result[:reason],
          iterations: agent_result[:iterations] || 0
        }
      end

      # Extract trade plan from synthesis
      def extract_trade_plan(agent_result)
        final_output = agent_result[:reason] || ""
        context = agent_result[:context] || []

        # Try to parse JSON from final output
        json_match = final_output.match(/\{[\s\S]*\}/)
        if json_match
          begin
            return JSON.parse(json_match[0])
          rescue JSON::ParserError
            # Continue
          end
        end

        # Check context
        context.each do |item|
          if item.is_a?(Hash) && (item[:result] || item["result"])
            result = item[:result] || item["result"]
            if result.is_a?(Hash) && (result[:trade_plan] || result["trade_plan"])
              return result[:trade_plan] || result["trade_plan"]
            end
          end
        end

        nil
      end

      # Check if MTF aligns with HTF
      def aligned_with_htf?(htf_result, mtf_result)
        return false unless mtf_result[:aligned_with_htf]

        # Additional alignment checks
        if @mode == :options_intraday
          # 15m regime must agree with 5m direction
          regime = htf_result[:regime]
          direction = mtf_result[:direction]

          case regime
          when "TREND_DAY", "VOLATILITY_EXPANSION"
            direction != "NEUTRAL"
          when "RANGE"
            false # Range = NO_TRADE
          else
            false
          end
        else
          # Daily trend must agree with 1H setup
          trend = htf_result[:trend]
          setup = mtf_result[:setup]

          case trend
          when "UP"
            setup != "NONE"
          when "DOWN"
            setup != "NONE"
          when "SIDEWAYS"
            false
          else
            false
          end
        end
      end

      # Helper extraction methods
      def extract_regime(result)
        extract_from_result(result, "regime") || "NO_TRADE"
      end

      def extract_tradable(result)
        extract_from_result(result, "tradable") != false
      end

      def extract_direction(result)
        extract_from_result(result, "direction") || "NEUTRAL"
      end

      def extract_momentum(result)
        extract_from_result(result, "momentum") || "WEAK"
      end

      def extract_alignment(result)
        extract_from_result(result, "aligned_with_htf") != false
      end

      def extract_entry_type(result)
        extract_from_result(result, "entry_type") || "BREAKOUT"
      end

      def extract_trigger(result)
        extract_from_result(result, "trigger") || ""
      end

      def extract_sl_level(result)
        extract_from_result(result, "sl_level") || 0
      end

      def extract_strike_candidates(result)
        final_output = result[:reason] || ""
        context = result[:context] || []

        # Try JSON parse
        json_match = final_output.match(/\{[\s\S]*\}/)
        if json_match
          begin
            parsed = JSON.parse(json_match[0])
            return parsed["candidates"] || parsed[:candidates] || []
          rescue JSON::ParserError
            # Continue
          end
        end

        # Check context
        context.each do |item|
          if item.is_a?(Hash) && (item[:result] || item["result"])
            result_data = item[:result] || item["result"]
            if result_data.is_a?(Hash) && (result_data[:candidates] || result_data["candidates"])
              return result_data[:candidates] || result_data["candidates"] || []
            end
          end
        end

        []
      end

      def extract_atm_strike(result)
        extract_from_result(result, "atm_strike") || 0
      end

      def extract_strike_reason(result)
        extract_from_result(result, "reason") || "No reason provided"
      end

      def extract_from_result(result, key)
        final_output = result[:reason] || ""
        context = result[:context] || []

        # Try JSON parse
        json_match = final_output.match(/\{[\s\S]*\}/)
        if json_match
          begin
            parsed = JSON.parse(json_match[0])
            return parsed[key] || parsed[key.to_sym]
          rescue JSON::ParserError
            # Continue
          end
        end

        # Check context
        context.each do |item|
          if item.is_a?(Hash) && (item[:result] || item["result"])
            result_data = item[:result] || item["result"]
            if result_data.is_a?(Hash)
              return result_data[key] || result_data[key.to_sym]
            end
          end
        end

        nil
      end

      # Create agent for timeframe analysis
      def create_agent(max_iterations:)
        analysis_registry = create_analysis_registry

        Ollama::Agent.new(
          client: @client,
          registry: analysis_registry,
          max_iterations: max_iterations,
          timeout: 30
        )
      end

      # Create analysis registry (only analysis tools)
      def create_analysis_registry
        registry = Ollama::Agent::ToolRegistry.new

        return registry unless @registry

        analysis_tools = %w[
          dhan.instrument.find
          dhan.market.ltp
          dhan.history.intraday
          dhan.history.daily
          dhan.option.chain
          dhan.option.expiries
        ]

        analysis_tools.each do |tool_name|
          descriptor = @registry.descriptor(tool_name)
          next unless descriptor

          registry.register(
            descriptor: descriptor.to_schema,
            handler: ->(args) { @registry.call(tool_name, args) }
          )
        end

        registry
      end

      # Create Ollama client
      def create_ollama_client
        base_url = ENV.fetch("OLLAMA_URL", "http://localhost:11434")
        Ollama::Client.new(host: base_url)
      end
    end
  end
end

