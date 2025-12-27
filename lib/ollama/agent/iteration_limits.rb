# frozen_string_literal: true

module Ollama
  class Agent
    # Production-safe iteration limits per agent type
    # Based on: iteration = 1 LLM call + 0-1 tool execution
    module IterationLimits
      # Analysis agents - allow deep reasoning
      ANALYSIS = 8 # 5-8 range for market analysis
      PLANNING = 4
      RESEARCH = 6

      # Validation agents - quick checks
      VALIDATION = 3 # 2-3 range for risk validation
      RISK_CHECK = 2

      # Execution agents - fast and bounded
      EXECUTION = 2
      TRADING_EXECUTION = 2 # 1-2 range, ≤3 for trading (safety)

      # Global limit: One trade = max 12 LLM calls total
      # (8 analysis + 3 validation + 2 execution = 13 theoretical max)
      # But typical: 6-8 analysis + 2 validation + 1 execution = 9-11 calls
      MAX_LLM_CALLS_PER_TRADE = 12

      # Monitoring agents - status checks
      MONITORING = 1
      STATUS_CHECK = 1

      # Debug/development agents - more lenient
      DEBUG = 10
      CURSOR_LIKE = 20 # For file editing, not trading

      # Default limits by category
      DEFAULT_LIMITS = {
        analysis: ANALYSIS,
        planning: PLANNING,
        research: RESEARCH,
        validation: VALIDATION,
        risk_check: RISK_CHECK,
        execution: EXECUTION,
        trading_execution: TRADING_EXECUTION,
        monitoring: MONITORING,
        status_check: STATUS_CHECK,
        debug: DEBUG,
        cursor_like: CURSOR_LIKE
      }.freeze

      # Get limit for agent type
      # @param agent_type [Symbol] Agent type
      # @return [Integer] Max iterations
      def self.limit_for(agent_type)
        DEFAULT_LIMITS[agent_type] || EXECUTION
      end

      # Validate iteration count is safe
      # @param count [Integer] Proposed iteration count
      # @param agent_type [Symbol] Agent type
      # @return [Boolean] Is safe?
      def self.safe?(count, agent_type)
        max = limit_for(agent_type)
        count <= max && count > 0
      end
    end
  end
end
