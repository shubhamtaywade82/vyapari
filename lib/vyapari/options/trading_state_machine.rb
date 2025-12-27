# frozen_string_literal: true

# Formal state machine for Vyapari options trading system
# Capital-safe architecture with bounded LLM calls

module Vyapari
  module Options
    class TradingStateMachine
      # State definitions
      STATES = {
        idle: "IDLE",
        market_analysis: "MARKET_ANALYSIS",
        plan_validation: "PLAN_VALIDATION",
        order_execution: "ORDER_EXECUTION",
        position_track: "POSITION_TRACK",
        completed: "COMPLETED",
        rejected: "REJECTED"
      }.freeze

      # Valid state transitions
      TRANSITIONS = {
        idle: [:market_analysis],
        market_analysis: %i[plan_validation rejected completed],
        plan_validation: %i[order_execution rejected],
        order_execution: %i[position_track rejected],
        position_track: [:completed],
        completed: [:idle],
        rejected: [:idle]
      }.freeze

      # State configurations
      STATE_CONFIGS = {
        idle: {
          llm_allowed: false,
          max_iterations: 0,
          purpose: "Wait for external trigger",
          triggers: %w[time signal webhook scheduled],
          output: "Transition to MARKET_ANALYSIS"
        },
        market_analysis: {
          llm_allowed: true,
          max_iterations: 8,
          agent: "Agent A",
          purpose: "Understand market context and generate TradePlan",
          allowed_tools: %w[
            dhan.instrument.find
            dhan.market.ltp
            dhan.market.quote
            dhan.history.intraday
            dhan.history.daily
            dhan.option.chain
            dhan.option.expiries
          ],
          blocked_tools: %w[
            dhan.funds.*
            dhan.order.*
            dhan.position.*
          ],
          output_schema: "TradePlan JSON",
          stop_conditions: %w[bias=NO_TRADE iteration_limit market_unclear]
        },
        plan_validation: {
          llm_allowed: true,
          max_iterations: 3,
          agent: "Agent B",
          purpose: "Convert TradePlan → ExecutablePlan OR Reject",
          allowed_tools: %w[
            dhan.funds.balance
            dhan.positions.list
            dhan.instrument.find
          ],
          blocked_tools: %w[
            dhan.order.*
            dhan.market.*
            dhan.history.*
          ],
          output_schema: "APPROVED/REJECTED with ExecutablePlan",
          hard_rules: %w[no_sl_reject risk_exceeded_reject funds_insufficient_reject]
        },
        order_execution: {
          llm_allowed: true,
          max_iterations: 2,
          agent: "Agent C",
          purpose: "Place exactly ONE order",
          allowed_tools: %w[
            dhan.super.place
            dhan.order.place
          ],
          blocked_tools: %w[
            dhan.funds.*
            dhan.market.*
            dhan.history.*
            dhan.option.*
          ],
          output_schema: "order_id",
          stop_conditions: %w[order_placed iteration_limit execution_failed]
        },
        position_track: {
          llm_allowed: false,
          max_iterations: 0,
          agent: "Rules Engine",
          purpose: "Real-time trade management",
          driven_by: %w[websocket tickcache deterministic_rules],
          responsibilities: %w[trailing_sl emergency_exit target_hit partial_fills kill_switch],
          output_schema: "Exit signal"
        },
        completed: {
          llm_allowed: false,
          max_iterations: 0,
          purpose: "Finalize trade lifecycle",
          actions: %w[persist_journal record_metrics reset_context],
          output: "Return to IDLE"
        },
        rejected: {
          llm_allowed: false,
          max_iterations: 0,
          purpose: "Stop cleanly on failure/rejection",
          actions: %w[log_rejection reset_context],
          output: "Return to IDLE"
        }
      }.freeze

      attr_reader :current_state, :state_history, :trade_plan, :executable_plan, :order_id

      def initialize
        @current_state = STATES[:idle]
        @state_history = []
        @trade_plan = nil
        @executable_plan = nil
        @order_id = nil
      end

      # Transition to new state
      # @param new_state [Symbol] Target state
      # @return [Boolean] Transition successful?
      def transition_to(new_state)
        new_state_sym = new_state.is_a?(Symbol) ? new_state : STATES.key(new_state)

        unless valid_transition?(@current_state, new_state_sym)
          raise InvalidTransitionError, "Cannot transition from #{@current_state} to #{new_state}"
        end

        @state_history << {
          from: @current_state,
          to: new_state,
          timestamp: Time.now
        }

        @current_state = new_state
        true
      end

      # Check if transition is valid
      # @param from [Symbol, String] Current state
      # @param to [Symbol, String] Target state
      # @return [Boolean] Is valid?
      def valid_transition?(from, to)
        from_sym = from.is_a?(Symbol) ? from : STATES.key(from)
        to_sym = to.is_a?(Symbol) ? to : STATES.key(to)

        TRANSITIONS[from_sym]&.include?(to_sym) || false
      end

      # Get state configuration
      # @param state [Symbol, String] State name
      # @return [Hash, nil] State configuration
      def state_config(state)
        state_sym = state.is_a?(Symbol) ? state : STATES.key(state)
        STATE_CONFIGS[state_sym]
      end

      # Check if LLM is allowed in current state
      # @return [Boolean] LLM allowed?
      def llm_allowed?
        config = state_config(@current_state)
        config && config[:llm_allowed] == true
      end

      # Get max iterations for current state
      # @return [Integer] Max iterations
      def max_iterations
        config = state_config(@current_state)
        config ? (config[:max_iterations] || 0) : 0
      end

      # Visual state machine diagram
      def self.diagram
        <<~DIAGRAM
          ┌─────────────────────────────────────────────────────────────┐
          │         VYAPARI OPTIONS TRADING STATE MACHINE               │
          │         (Capital-Safe Multi-Agent Architecture)             │
          └─────────────────────────────────────────────────────────────┘

          ┌──────────────────────────┐
          │          IDLE            │  ❌ NO LLM
          │  (Waiting for trigger)   │  Max Iterations: 0
          └───────────┬──────────────┘
                      │
                      │ Time / Signal / Webhook
                      ▼
          ┌──────────────────────────┐
          │   MARKET ANALYSIS STATE  │  ✅ LLM ALLOWED
          │   (Agent A – LLM)        │  Max Iterations: 5-8
          │                          │  Tools: market, historical, option chain
          │  Output: TradePlan JSON  │  ❌ NO funds, NO orders
          └───────────┬──────────────┘
                      │ TradePlan JSON
                      ▼
          ┌──────────────────────────┐
          │  PLAN VALIDATION STATE   │  ✅ LLM ALLOWED
          │  (Agent B – LLM + Rules) │  Max Iterations: 2-3
          │                          │  Tools: funds, positions, risk checks
          │  Output: Approved/Reject │  ❌ NO market data, NO orders
          └───────────┬──────────────┘
                      │ Approved?
                  ┌───┴────┐
                  │        │
                  │ NO     │ YES
                  │        │
                  ▼        ▼
          ┌──────────────┐  ┌──────────────────────────┐
          │   REJECTED   │  │  ORDER EXECUTION STATE   │  ✅ LLM ALLOWED
          │ (Stop clean) │  │  (Agent C – LLM, 1-2)   │  Max Iterations: 1-2
          └──────────────┘  │                          │  Tools: super_order only
                            │  Output: Order ID        │  ❌ NO analysis tools
                            └───────────┬──────────────┘
                                        │ Order ID
                                        ▼
                            ┌──────────────────────────┐
                            │ POSITION TRACKING STATE  │  ❌ NO LLM
                            │ (NO LLM – WS + Rules)    │  Max Iterations: 0
                            │                          │  Driven by: WebSocket
                            │  Output: Exit signal     │  Deterministic rules only
                            └───────────┬──────────────┘
                                        │ Exit / SL / TP
                                        ▼
                            ┌──────────────────────┐
                            │      COMPLETED       │  ❌ NO LLM
                            │ (Journal + Metrics)  │  Max Iterations: 0
                            └──────────────────────┘
                                        │
                                        └──→ Return to IDLE

          🔑 KEY RULES:
          ✅ Only 3 states call LLM (Analysis, Validation, Execution)
          ✅ Only 1 state places orders (Execution)
          ✅ 0 LLM calls after order placement (Position Tracking)
          ✅ Max 12 LLM calls per trade (8 + 3 + 2 = 13 theoretical max)
        DIAGRAM
      end

      # Get summary of state machine
      # @return [Hash] State machine summary
      def summary
        {
          current_state: @current_state,
          llm_allowed: llm_allowed?,
          max_iterations: max_iterations,
          state_history: @state_history,
          trade_plan: @trade_plan ? "Present" : "None",
          executable_plan: @executable_plan ? "Present" : "None",
          order_id: @order_id
        }
      end
    end

    class InvalidTransitionError < StandardError; end
  end
end

