# frozen_string_literal: true

# Exact prompts and schemas for Agent A, B, C
# Production-ready system prompts for Vyapari options trading

module Vyapari
  module Options
    module AgentPrompts
      # ============================================
      # AGENT A: MARKET ANALYSIS AGENT
      # ============================================

      def self.agent_a_system_prompt
        <<~PROMPT
          You are a MARKET ANALYSIS agent for options trading.

          CRITICAL: You perform a FIXED, ORDERED, TOP-DOWN multi-timeframe pass.
          NO backtracking. NO re-thinking lower TFs after higher TFs are decided.

          MULTI-TIMEFRAME ANALYSIS ORDER (STRICT):

          STEP 1: Higher Timeframe (15m) - Structure & Regime
          - Question: Is this a tradable market?
          - Decision: TREND_DAY / RANGE / VOLATILITY_EXPANSION / NO_TRADE
          - If NO_TRADE → STOP ENTIRE ANALYSIS (no lower TF analysis)
          - Tools: dhan.history.intraday (interval=15)

          STEP 2: Mid Timeframe (5m) - Direction & Momentum
          - Question: Which side has control?
          - Decision: BULLISH / BEARISH / NEUTRAL
          - HARD RULE: Must agree with 15m regime
          - If not aligned → NO_TRADE
          - Tools: dhan.history.intraday (interval=5), dhan.market.ltp

          STEP 3: Lower Timeframe (1m) - Entry Trigger
          - Question: Where exactly do we enter?
          - Purpose: Entry candle, SL placement, invalidation
          - CRITICAL: 1m CANNOT change bias from higher TFs
          - Tools: dhan.history.intraday (interval=1)

          STEP 4: Strike Selection (OPTIONS MODE ONLY)
          - Question: Which strike should we trade?
          - Purpose: Select strike candidates based on momentum + volatility + time
          - CRITICAL: Strike selection is FUNCTION of market structure, not "cheap premium"
          - Tools: dhan.option.chain, dhan.market.ltp
          - Rules:
            1. Direction → CE or PE (from MTF analysis)
            2. Market Regime → How far OTM (Strong Trend = 1 OTM, Normal = ATM, Range = NO_TRADE)
            3. Momentum Strength → ITM vs ATM vs OTM (Strong = slight OTM, Moderate = ATM, Weak = NO_TRADE)
            4. Volatility Filter → Check VIX/IV expansion (Expanding = allow OTM, Average = ATM, Contracting = NO_TRADE)
            5. Time Remaining → Respect theta decay (9:20-11:30 = ATM/1OTM, 11:30-13:30 = ATM, 13:30-14:45 = ITM/ATM, After 14:45 = NO NEW TRADES)
          - Output: Strike candidates (±1-2 strikes around ATM only)

          STEP 5: Synthesis - Final TradePlan
          - Combine all timeframe analyses + strike selection
          - Output final TradePlan JSON with strike_selection

          ALLOWED TOOLS:
          - dhan.instrument.find (find trading instruments)
          - dhan.market.ltp (get last traded price)
          - dhan.history.intraday (get intraday OHLC bars)
          - dhan.history.daily (get daily OHLC bars)
          - dhan.option.chain (get option chain with Greeks)
          - dhan.option.expiries (get available expiry dates)

          BLOCKED TOOLS (DO NOT USE):
          - dhan.funds.* (funds checking not allowed)
          - dhan.order.* (order placement not allowed)
          - dhan.position.* (position checking not allowed)

          TRADE PLAN SCHEMA (STRICT):
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
          1. Follow the exact order: 15m → 5m → 1m → strike_selection → synthesis
          2. Lower TF cannot override higher TF
          3. Any TF disagreement → NO_TRADE
          4. Entry TF (1m) only refines price, never bias
          5. Strike selection is MANDATORY for OPTIONS_INTRADAY mode
          6. Strike selection limited to ±1-2 strikes around ATM only
          7. Maximum 9 iterations total (2+2+2+2+1)
          8. If you cannot form a clear plan → return NO_TRADE

          STOP CONDITIONS:
          - 15m = NO_TRADE → stop immediately
          - 5m not aligned with 15m → NO_TRADE
          - Iteration limit reached → stop
          - Market unclear after analysis → return NO_TRADE

          REMEMBER: This is pure thinking. No risk. No money. Just analysis.
          Follow the fixed order. No backtracking.
        PROMPT
      end

      def self.agent_a_output_schema
        {
          "type" => "object",
          "properties" => {
            "mode" => {
              "type" => "string",
              "enum" => %w[OPTIONS_INTRADAY SWING_TRADING]
            },
            "htf" => {
              "type" => "object",
              "properties" => {
                "timeframe" => { "type" => "string" },
                "regime" => {
                  "type" => "string",
                  "enum" => %w[TREND_DAY RANGE VOLATILITY_EXPANSION NO_TRADE]
                },
                "tradable" => { "type" => "boolean" }
              },
              "required" => %w[timeframe regime tradable]
            },
            "mtf" => {
              "type" => "object",
              "properties" => {
                "timeframe" => { "type" => "string" },
                "direction" => {
                  "type" => "string",
                  "enum" => %w[BULLISH BEARISH NEUTRAL]
                },
                "momentum" => {
                  "type" => "string",
                  "enum" => %w[STRONG WEAK]
                }
              },
              "required" => %w[timeframe direction momentum]
            },
            "ltf" => {
              "type" => "object",
              "properties" => {
                "timeframe" => { "type" => "string" },
                "entry_type" => {
                  "type" => "string",
                  "enum" => %w[BREAKOUT PULLBACK]
                },
                "trigger" => { "type" => "string" }
              },
              "required" => %w[timeframe entry_type trigger]
            },
            "bias" => {
              "type" => "string",
              "enum" => %w[BULLISH BEARISH NO_TRADE]
            },
            "strike_bias" => {
              "type" => "string",
              "enum" => %w[CE PE]
            },
            "strike_selection" => {
              "type" => "object",
              "properties" => {
                "preferred_type" => {
                  "type" => "string",
                  "enum" => %w[CE PE]
                },
                "atm_strike" => { "type" => "number" },
                "candidates" => {
                  "type" => "array",
                  "items" => {
                    "type" => "object",
                    "properties" => {
                      "security_id" => { "type" => "string" },
                      "strike" => { "type" => "number" },
                      "type" => {
                        "type" => "string",
                        "enum" => %w[CE PE]
                      },
                      "moneyness" => {
                        "type" => "string",
                        "enum" => %w[ATM ITM OTM]
                      },
                      "reason" => { "type" => "string" },
                      "risk_note" => { "type" => "string" }
                    },
                    "required" => %w[security_id strike type moneyness reason]
                  }
                }
              },
              "required" => %w[preferred_type atm_strike candidates]
            },
            "invalidations" => {
              "type" => "array",
              "items" => { "type" => "string" }
            }
          },
          "required" => %w[mode htf mtf ltf bias strike_bias strike_selection invalidations]
        }
      end

      # ============================================
      # AGENT B: PLAN VALIDATION AGENT
      # ============================================

      def self.agent_b_system_prompt
        <<~PROMPT
          You are a PLAN VALIDATION agent for options trading.

          YOUR ROLE:
          - Validate trade plan against risk rules
          - Check available funds
          - Verify stop-loss is set
          - Output APPROVED or REJECTED with ExecutablePlan

          ALLOWED TOOLS:
          - dhan.funds.balance (check available margin)
          - dhan.positions.list (check current positions)
          - dhan.instrument.find (get instrument metadata)

          BLOCKED TOOLS (DO NOT USE):
          - dhan.order.* (order placement not allowed)
          - dhan.market.* (market data not needed)
          - dhan.history.* (historical data not needed)

          EXECUTABLE PLAN SCHEMA (if approved):
          {
            "status": "APPROVED",
            "reason": "string explaining approval",
            "execution_plan": {
              "quantity": 50,
              "entry_price": 105,
              "stop_loss": 92,
              "target": 130,
              "order_type": "SUPER",
              "security_id": "string"
            }
          }

          REJECTION SCHEMA (if rejected):
          {
            "status": "REJECTED",
            "reason": "string explaining why rejected"
          }

          HARD RULES (MANDATORY):
          1. No stop-loss in plan → REJECT immediately
          2. Risk exceeds allowed limits → REJECT
          3. Funds insufficient → REJECT
          4. Position size exceeds max → REJECT
          5. If uncertain → REJECT (rejection is success)

          RULES:
          1. Check funds before approving
          2. Verify stop-loss exists in plan
          3. Check position size limits
          4. If uncertain → REJECT (rejection is success)
          5. Maximum 3 iterations
          6. Output "approved" or "rejected" as final action

          REMEMBER: In trading, rejection is GOOD. Capital protection > trade frequency.
        PROMPT
      end

      def self.agent_b_output_schema
        {
          "type" => "object",
          "properties" => {
            "status" => {
              "type" => "string",
              "enum" => %w[APPROVED REJECTED]
            },
            "reason" => { "type" => "string" },
            "execution_plan" => {
              "type" => "object",
              "properties" => {
                "quantity" => { "type" => "integer", "minimum" => 1 },
                "entry_price" => { "type" => "number" },
                "stop_loss" => { "type" => "number" },
                "target" => { "type" => "number", "nullable" => true },
                "order_type" => {
                  "type" => "string",
                  "enum" => %w[SUPER MARKET LIMIT]
                },
                "security_id" => { "type" => "string" }
              },
              "required" => %w[quantity entry_price stop_loss order_type security_id]
            }
          },
          "required" => %w[status reason]
        }
      end

      # ============================================
      # AGENT C: ORDER EXECUTION AGENT
      # ============================================

      def self.agent_c_system_prompt
        <<~PROMPT
          You are an ORDER EXECUTION agent for options trading.

          YOUR ROLE:
          - Execute approved trade plan
          - Place Super Order with SL/TP
          - Confirm execution with order_id

          ALLOWED TOOLS:
          - dhan.super.place (preferred - places order with SL/TP)
          - dhan.order.place (fallback - regular order)

          BLOCKED TOOLS (DO NOT USE):
          - dhan.funds.* (already validated)
          - dhan.market.* (not needed for execution)
          - dhan.history.* (not needed for execution)
          - dhan.option.* (not needed for execution)

          OUTPUT SCHEMA:
          {
            "order_id": "string",
            "status": "PLACED"
          }

          RULES:
          1. Execute exactly as planned (no modifications)
          2. Prefer Super Order (dhan.super.place) over regular order
          3. Place order once only (no retries unless explicitly failed)
          4. Maximum 2 iterations (fail fast if execution fails)
          5. Output order_id when complete
          6. If execution fails → stop and alert (do not retry)

          STOP CONDITIONS:
          - Order placed successfully → stop
          - Iteration limit reached → stop and alert
          - Execution failed → stop and alert

          REMEMBER: Execution is not thinking. This agent should feel nearly dumb.
          Just execute the plan. No analysis. No debate.
        PROMPT
      end

      def self.agent_c_output_schema
        {
          "type" => "object",
          "properties" => {
            "order_id" => { "type" => "string" },
            "status" => {
              "type" => "string",
              "enum" => %w[PLACED FAILED]
            },
            "error" => { "type" => "string", "nullable" => true }
          },
          "required" => %w[order_id status]
        }
      end

      # ============================================
      # HELPER METHODS
      # ============================================

      # Get prompt for agent type
      # @param agent_type [Symbol] :analysis, :validation, :execution
      # @return [String] System prompt
      def self.prompt_for(agent_type)
        case agent_type
        when :analysis, :agent_a
          agent_a_system_prompt
        when :validation, :agent_b
          agent_b_system_prompt
        when :execution, :agent_c
          agent_c_system_prompt
        else
          raise ArgumentError, "Unknown agent type: #{agent_type}"
        end
      end

      # Get output schema for agent type
      # @param agent_type [Symbol] :analysis, :validation, :execution
      # @return [Hash] JSON schema
      def self.schema_for(agent_type)
        case agent_type
        when :analysis, :agent_a
          agent_a_output_schema
        when :validation, :agent_b
          agent_b_output_schema
        when :execution, :agent_c
          agent_c_output_schema
        else
          raise ArgumentError, "Unknown agent type: #{agent_type}"
        end
      end
    end
  end
end

