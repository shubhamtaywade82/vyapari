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

          YOUR ROLE:
          - Analyze market data, historical patterns, and option chains
          - Generate a trade plan with entry, stop-loss, and target
          - DO NOT place any orders
          - DO NOT check funds or risk limits
          - Output final plan as JSON matching the TradePlan schema

          ALLOWED TOOLS:
          - dhan.instrument.find (find trading instruments)
          - dhan.market.ltp (get last traded price)
          - dhan.market.quote (get full market quote)
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
            "bias": "BULLISH | BEARISH | NO_TRADE",
            "setup": "BREAKOUT | REVERSAL | TREND | RANGE",
            "strike": {
              "security_id": "string (DhanHQ security ID)",
              "type": "CE | PE",
              "moneyness": "ATM | ITM | OTM"
            },
            "entry_logic": "text explanation of why this trade",
            "invalidation": "text explanation of when to exit"
          }

          RULES:
          1. Use tools to gather market data (OHLC, option chain, LTP)
          2. Analyze structure, trend, volatility, momentum
          3. If market is unclear or choppy, return bias: "NO_TRADE"
          4. Output plan when complete (action: "final")
          5. Maximum 8 iterations maximum
          6. If you cannot form a clear plan in 8 thoughts → return NO_TRADE

          STOP CONDITIONS:
          - Bias = NO_TRADE → stop immediately
          - Iteration limit reached → stop
          - Market unclear after analysis → return NO_TRADE

          REMEMBER: This is pure thinking. No risk. No money. Just analysis.
        PROMPT
      end

      def self.agent_a_output_schema
        {
          "type" => "object",
          "properties" => {
            "bias" => {
              "type" => "string",
              "enum" => %w[BULLISH BEARISH NO_TRADE]
            },
            "setup" => {
              "type" => "string",
              "enum" => %w[BREAKOUT REVERSAL TREND RANGE]
            },
            "strike" => {
              "type" => "object",
              "properties" => {
                "security_id" => { "type" => "string" },
                "type" => {
                  "type" => "string",
                  "enum" => %w[CE PE]
                },
                "moneyness" => {
                  "type" => "string",
                  "enum" => %w[ATM ITM OTM]
                }
              },
              "required" => %w[security_id type moneyness]
            },
            "entry_logic" => { "type" => "string" },
            "invalidation" => { "type" => "string" }
          },
          "required" => %w[bias setup strike entry_logic invalidation]
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

