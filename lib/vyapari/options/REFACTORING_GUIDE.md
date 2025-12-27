# Vyapari Options Trading: Complete Refactoring Guide

## Overview

This guide maps the **complete multi-agent state machine** to Vyapari's existing codebase, with **production-safe iteration numbers** and **concrete implementation**.

---

## 1. Full Multi-Agent State Machine

### Visual Diagram

```
IDLE → MARKET_ANALYSIS → PLAN_VALIDATION → ORDER_EXECUTION → POSITION_TRACK → COMPLETE
  │         │                  │                  │                │
  │         └─ NO_TRADE ───────┴──────────────────┴────────────────┘
  │         └─ Failure ────────→ REJECTED
```

### State Definitions

| State             | Agent        | LLM?   | Max Iterations | Purpose            |
| ----------------- | ------------ | ------ | -------------- | ------------------ |
| `IDLE`            | None         | No     | 0              | Initial state      |
| `MARKET_ANALYSIS` | Agent A      | Yes    | 8              | Produce TradePlan  |
| `PLAN_VALIDATION` | Agent B      | Yes    | 3              | Validate & Approve |
| `ORDER_EXECUTION` | Agent C      | Yes    | 2              | Place Order        |
| `POSITION_TRACK`  | Rules Engine | **No** | 0              | WebSocket tracking |
| `COMPLETE`        | None         | No     | 0              | Success            |
| `REJECTED`        | None         | No     | 0              | Failure/Rejection  |

---

## 2. Agent Specifications

### Agent A: Market Analysis Agent

**Purpose:** Produce TradePlan JSON (NO orders, NO risk decisions)

**Inputs:**
- Instrument (NIFTY / BANKNIFTY)
- Timeframe preference
- Recent OHLC (historical API)
- Option chain snapshot
- Volatility context

**Tools Allowed:**
```
✅ dhan.instrument.find
✅ dhan.market.ltp
✅ dhan.market.quote
✅ dhan.history.intraday
✅ dhan.history.daily
✅ dhan.option.chain
✅ dhan.option.expiries
❌ dhan.order.* (HARD BLOCKED)
❌ dhan.funds.* (HARD BLOCKED)
```

**Output Schema (STRICT):**
```json
{
  "bias": "BULLISH | BEARISH | NO_TRADE",
  "setup": "BREAKOUT | REVERSAL | TREND | RANGE",
  "strike": {
    "security_id": "string",
    "type": "CE | PE",
    "moneyness": "ATM | ITM | OTM"
  },
  "entry_logic": "text explanation",
  "invalidation": "text explanation"
}
```

**Iteration Budget:** **5-8 iterations**

**Rationale:**
- Market structure + options require context
- But must still terminate
- If it can't form a plan in 8 thoughts → market is unclear → return `NO_TRADE`

**System Prompt:**
```
You are a MARKET ANALYSIS agent for options trading.

YOUR ROLE:
- Analyze market data, historical patterns, and option chains
- Generate a trade plan with entry, stop-loss, and target
- DO NOT place any orders
- DO NOT check funds or risk limits
- Output final plan as JSON matching the TradePlan schema

RULES:
- Use tools to gather market data
- Analyze structure, trend, volatility, momentum
- If market is unclear or choppy, return bias: "NO_TRADE"
- Output plan when complete (action: "final")
- Maximum 8 iterations
```

---

### Agent B: Plan Validation Agent

**Purpose:** Turn TradePlan → ExecutablePlan OR Reject

**Inputs:**
- TradePlan JSON
- Funds balance
- Risk config (max loss, lot size)
- Instrument trading flags

**Tools Allowed:**
```
✅ dhan.funds.balance
✅ dhan.positions.list
✅ dhan.instrument.find
❌ market data (BLOCKED)
❌ orders (BLOCKED)
```

**Output Schema:**
```json
{
  "status": "APPROVED | REJECTED",
  "reason": "string",
  "execution_plan": {
    "quantity": 50,
    "entry_price": 105,
    "stop_loss": 92,
    "target": 130,
    "order_type": "SUPER",
    "security_id": "string"
  }
}
```

**Iteration Budget:** **2-3 iterations**

**Rationale:**
- This is rule checking, not discovery
- If undecided → reject
- **In trading, rejection is success**

**System Prompt:**
```
You are a PLAN VALIDATION agent for options trading.

YOUR ROLE:
- Validate trade plan against risk rules
- Check available funds
- Verify stop-loss is set
- Output APPROVED or REJECTED with ExecutablePlan

RULES:
- Check funds before approving
- Verify stop-loss exists in plan
- Check position size limits
- If uncertain → REJECT (rejection is success)
- Maximum 3 iterations
- Output "approved" or "rejected" as final action
```

---

### Agent C: Order Execution Agent

**Purpose:** Translate ExecutablePlan → Order ID

**Tools Allowed:**
```
✅ dhan.super.place (preferred)
✅ dhan.order.place (fallback)
❌ everything else (BLOCKED)
```

**Output Schema:**
```json
{
  "order_id": "112111182198",
  "status": "PLACED"
}
```

**Iteration Budget:** **1-2 iterations MAX**

**Rationale:**
- Execution is not thinking
- Retrying more than once = danger
- If execution fails → escalate to human / halt

**System Prompt:**
```
You are an ORDER EXECUTION agent for options trading.

YOUR ROLE:
- Execute approved trade plan
- Place Super Order with SL/TP
- Confirm execution with order_id

RULES:
- Execute exactly as planned
- Prefer Super Order (dhan.super.place) over regular order
- Place order once only
- Maximum 2 iterations
- Output order_id when complete
```

---

## 3. Production-Safe Iteration Numbers

| Phase             | Iterations | LLM Calls | Justification                         |
| ----------------- | ---------- | --------- | ------------------------------------- |
| **Analysis**      | 5-8        | 5-8       | Discovery allowed, but must terminate |
| **Validation**    | 2-3        | 2-3       | Reject fast if uncertain              |
| **Execution**     | 1-2        | 1-2       | Never loop, fail fast                 |
| **Position Mgmt** | 0          | 0         | WebSocket only, NO LLM                |

### Hard Global Limit

> **One trade = max 12 LLM calls total**

**Typical:** 6-8 (analysis) + 2 (validation) + 1 (execution) = **9-11 calls**
**Maximum:** 8 (analysis) + 3 (validation) + 2 (execution) = **13 calls**

Anything beyond that:
- Burns latency
- Increases hallucination risk
- Adds zero edge

---

## 4. Position Tracking (NO LLM)

**Driven by:**
- DhanHQ WebSocket
- TickCache
- Deterministic rules

**Responsibilities:**
- Trailing SL
- Emergency exits
- Target hit
- Partial fills

**Why NO LLM?**
- LLM latency is unacceptable
- Determinism matters more than "reasoning"
- You already built this correctly

---

## 5. Implementation Files

### Core Files Created

1. **`lib/vyapari/options/phased_agent.rb`**
   - Main phased agent orchestrator
   - Runs all 3 phases sequentially
   - Manages state transitions
   - Extracts plans from LLM outputs

2. **`lib/vyapari/options/state_machine.rb`**
   - State machine constants
   - Valid transitions
   - Agent configurations
   - Visual diagram generator

3. **`lib/vyapari/options/phased_usage_example.rb`**
   - Complete usage examples
   - Iteration limits documentation
   - State machine visualization

### Integration Points

**Replace existing `Vyapari::Options::Agent` with:**

```ruby
# Old way (single agent, 50 steps)
agent = Vyapari::Options::Agent.new
result = agent.run("Analyze NIFTY options buying")

# New way (phased agents, bounded)
phased_agent = Vyapari::Options::PhasedAgent.new(
  registry: registry,
  safety_gate: safety_gate
)
result = phased_agent.run("Analyze NIFTY options buying")
```

---

## 6. Migration Steps

### Step 1: Setup Tool Registry

```ruby
registry = Ollama::Agent::ToolRegistry.new
Ollama::Agent::Tools::DhanComplete.register_all(registry: registry)
```

### Step 2: Setup Safety Gate

```ruby
safety_gate = Ollama::Agent::SafetyGate.new(
  rules: Ollama::Agent::SafetyGate.trading_rules(
    max_position_size: 10_000,
    require_stoploss: true,
    dry_run_only: true
  )
)
```

### Step 3: Create Phased Agent

```ruby
phased_agent = Vyapari::Options::PhasedAgent.new(
  registry: registry,
  safety_gate: safety_gate
)
```

### Step 4: Run Workflow

```ruby
result = phased_agent.run("Analyze NIFTY options buying")
```

### Step 5: Handle Results

```ruby
case result[:final_status]
when "executed"
  # Order placed, track position
  track_position(result[:order_id])
when "no_trade"
  # Market unclear, no action
  log_no_trade(result[:final_output])
when "validation_failed"
  # Risk check failed, log rejection
  log_rejection(result[:final_output])
when "execution_failed"
  # Order failed, escalate
  escalate_to_human(result[:final_output])
end
```

---

## 7. Key Differences from Old System

| Aspect                | Old System             | New System                |
| --------------------- | ---------------------- | ------------------------- |
| **Architecture**      | Single agent, 50 steps | 3 phased agents, bounded  |
| **Iterations**        | Up to 50 (unbounded)   | 8 + 3 + 2 = 13 max        |
| **Tool Access**       | All tools available    | Phase-specific filtering  |
| **Safety**            | Mixed with analysis    | Separate validation phase |
| **Execution**         | Can loop               | 1-2 iterations max        |
| **Position Tracking** | N/A                    | WebSocket only (NO LLM)   |

---

## 8. Testing Strategy

### Unit Tests

1. **Test each phase independently**
   - Mock tool responses
   - Verify iteration limits
   - Check tool filtering

2. **Test state transitions**
   - Valid transitions
   - Invalid transitions (should fail)
   - Early exits

3. **Test plan extraction**
   - TradePlan from analysis
   - ExecutablePlan from validation
   - Order ID from execution

### Integration Tests

1. **End-to-end workflow**
   - Analysis → Validation → Execution
   - With real tool registry (dry-run mode)

2. **Failure scenarios**
   - Analysis fails → should reject
   - Validation fails → should reject
   - Execution fails → should escalate

---

## 9. Production Deployment Checklist

- [ ] Tool registry configured with all DhanHQ tools
- [ ] Safety gate configured with risk rules
- [ ] Dry-run mode enabled for testing
- [ ] Iteration limits enforced (hard caps)
- [ ] Tool filtering per phase verified
- [ ] Position tracking separated (NO LLM)
- [ ] Error handling for each phase
- [ ] Logging for audit trail
- [ ] Monitoring for iteration counts
- [ ] Alerting for execution failures

---

## 10. Next Steps (After Refactoring)

1. **Add RAG** - Historical trade patterns
2. **Multi-symbol screening** - Parallel analysis agents
3. **Journaling** - Trade plan persistence
4. **Backtesting** - Replay historical plans
5. **Performance metrics** - Track phase success rates

---

## Summary

✅ **Phase-based architecture** = Safety + Clarity
✅ **Bounded iterations** = No runaway loops
✅ **Tool filtering** = Phase-specific capabilities
✅ **Stop conditions** = Guaranteed termination
✅ **Production-safe limits** = Capital protection
✅ **Position tracking** = WebSocket only (NO LLM)

**Failure is not a bug — failure is a safety feature.**

