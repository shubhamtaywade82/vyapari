# frozen_string_literal: true

# State machine for Vyapari options trading workflow
# Visual representation of the multi-agent system

module Vyapari
  module Options
    # State machine constants and transitions
    class StateMachine
      STATES = {
        idle: "IDLE",
        market_analysis: "MARKET_ANALYSIS",
        plan_validation: "PLAN_VALIDATION",
        order_execution: "ORDER_EXECUTION",
        position_track: "POSITION_TRACK",
        complete: "COMPLETE",
        rejected: "REJECTED"
      }.freeze

      # Valid state transitions
      TRANSITIONS = {
        idle: [:market_analysis],
        market_analysis: %i[plan_validation rejected complete],
        plan_validation: %i[order_execution rejected],
        order_execution: %i[position_track rejected],
        position_track: [:complete],
        complete: [],
        rejected: []
      }.freeze

      # Agent mapping per state
      AGENT_MAPPING = {
        market_analysis: {
          agent: "Analysis Agent",
          max_iterations: 8,
          tools: %w[
            dhan.instrument.find
            dhan.market.ltp
            dhan.history.intraday
            dhan.option.chain
            dhan.option.expiries
          ],
          output: "TradePlan JSON",
          llm_allowed: true
        },
        plan_validation: {
          agent: "Validation Agent",
          max_iterations: 3,
          tools: %w[
            dhan.funds.balance
            dhan.positions.list
            dhan.instrument.find
          ],
          output: "ExecutablePlan OR Reject",
          llm_allowed: true
        },
        order_execution: {
          agent: "Execution Agent",
          max_iterations: 2,
          tools: %w[
            dhan.super.place
            dhan.order.place
          ],
          output: "order_id",
          llm_allowed: true
        },
        position_track: {
          agent: "Position Tracker",
          max_iterations: 0,
          tools: [],
          output: "Exit signal",
          llm_allowed: false # WebSocket + deterministic rules only
        }
      }.freeze

      # Check if transition is valid
      # @param from [Symbol] Current state
      # @param to [Symbol] Target state
      # @return [Boolean] Is transition valid?
      def self.valid_transition?(from, to)
        TRANSITIONS[from]&.include?(to) || false
      end

      # Get agent config for state
      # @param state [Symbol] State name
      # @return [Hash, nil] Agent configuration
      def self.agent_config(state)
        AGENT_MAPPING[state]
      end

      # Visual state machine diagram (ASCII)
      def self.diagram
        <<~DIAGRAM
          ┌─────────────────────────────────────────────────────────────┐
          │              VYAPARI OPTIONS TRADING STATE MACHINE          │
          └─────────────────────────────────────────────────────────────┘

          ┌────────────┐
          │    IDLE    │
          └─────┬──────┘
                │ (time / signal / webhook)
                ▼
          ┌──────────────────┐
          │ MARKET_ANALYSIS  │  ← Agent A (LLM, 8 iterations max)
          │                  │  Tools: market, historical, option chain
          │  Output:         │  Output: TradePlan JSON
          │  TradePlan       │  NO trading allowed
          └─────┬────────────┘
                │
                ├─ Success → TradePlan
                │
                └─ Failure/NO_TRADE → REJECTED/COMPLETE
                     │
                     ▼
          ┌──────────────────┐
          │ PLAN_VALIDATION  │  ← Agent B (LLM, 3 iterations max)
          │                  │  Tools: funds, positions, risk checks
          │  Output:         │  Output: APPROVED / REJECTED
          │  ExecutablePlan  │  Paranoid by design
          └─────┬────────────┘
                │
                ├─ Approved → ExecutablePlan
                │
                └─ Rejected → REJECTED
                     │
                     ▼
          ┌──────────────────┐
          │ ORDER_EXECUTION  │  ← Agent C (LLM, 2 iterations max)
          │                  │  Tools: super_order, order.place
          │  Output:         │  Output: order_id
          │  order_id        │  Nearly dumb (just execute)
          └─────┬────────────┘
                │
                ├─ Success → order_id
                │
                └─ Failure → REJECTED
                     │
                     ▼
          ┌──────────────────┐
          │ POSITION_TRACK   │  ← NO LLM (WebSocket + rules)
          │                  │  Tools: WebSocket ticks
          │  Output:         │  Output: Exit signal
          │  Exit signal     │  Deterministic only
          └─────┬────────────┘
                │
                └─ Exit → COMPLETE

          ┌────────────┐
          │  COMPLETE  │
          └────────────┘

          ┌────────────┐
          │  REJECTED  │
          └────────────┘

          HARD GLOBAL LIMIT: One trade = max 12 LLM calls total
          (8 analysis + 3 validation + 2 execution = 13 max, but typically 8-10)
        DIAGRAM
      end
    end
  end
end
