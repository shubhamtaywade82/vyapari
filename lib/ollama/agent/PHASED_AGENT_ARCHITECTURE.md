# Phase-Based Multi-Agent Architecture

## Core Principle

> **1 Iteration = 1 LLM Call + 0-1 Tool Execution**

**Iterations ≠ Tools**
**Iterations ≠ Steps**
**Iterations = Thinking Cycles**

---

## State Machine

```
┌─────────────────────────────────────────────────────────────┐
│                    OPTIONS TRADING WORKFLOW                  │
└─────────────────────────────────────────────────────────────┘

START
  │
  ▼
┌─────────────────────┐
│  PHASE 1: ANALYSIS  │  Max: 8 iterations
│                     │  Tools: market, historical, option chain
│  - Find instrument  │  Output: Trade Plan JSON
│  - Fetch data       │  NO trading allowed
│  - Analyze          │
│  - Generate plan    │
└─────────────────────┘
  │
  ├─ Success → Trade Plan
  │
  └─ Failure → EXIT (analysis_failed)
       │
       ▼
┌─────────────────────┐
│ PHASE 2: VALIDATION │  Max: 3 iterations
│                     │  Tools: funds, positions, risk checks
│  - Check funds      │  Output: APPROVED / REJECTED
│  - Verify SL        │
│  - Check limits     │
└─────────────────────┘
  │
  ├─ Approved
  │
  └─ Rejected → EXIT (validation_failed)
       │
       ▼
┌─────────────────────┐
│ PHASE 3: EXECUTION  │  Max: 2 iterations (≤3 for trading)
│                     │  Tools: super_order, order.place
│  - Place order      │  Output: order_id
│  - Confirm          │
└─────────────────────┘
  │
  └─ Complete → EXIT (executed)
```

---

## Iteration Limits (Production-Safe)

| Agent Type          | Max Iterations | Rationale                          |
| ------------------- | -------------- | ---------------------------------- |
| **Analysis**        | 8              | Deep reasoning allowed              |
| **Planning**        | 4              | Strategy planning                   |
| **Research**        | 6              | Data gathering                      |
| **Validation**      | 3              | Quick checks only                   |
| **Risk Check**      | 2              | Fast validation                     |
| **Execution**       | 2              | Fast execution                      |
| **Trading Execution**| **2**         | **≤3 for safety (CRITICAL)**        |
| **Monitoring**      | 1              | Status checks                       |
| **Status Check**    | 1              | Quick lookups                       |
| **Debug**           | 10             | Development only                    |
| **Cursor-like**     | 20             | File editing (NOT trading)          |

---

## Why Phase Separation?

### ❌ WRONG: Single Agent with 15 Iterations

```
Agent (15 iterations)
├─ Find instrument
├─ Fetch data
├─ Analyze
├─ Check funds
├─ Validate risk
├─ Place order
└─ ... (unbounded thinking = dangerous)
```

**Problems:**
- No clear boundaries
- Can loop forever
- Risk validation mixed with execution
- Hard to debug
- Capital risk

### ✅ RIGHT: Phase-Based Agents

```
Analysis Agent (8 iterations)
└─ Output: Trade Plan

Validation Agent (3 iterations)
└─ Output: APPROVED / REJECTED

Execution Agent (2 iterations)
└─ Output: order_id
```

**Benefits:**
- Clear boundaries
- Bounded thinking per phase
- Safety gates between phases
- Easy to debug
- Capital protection

---

## Stop Conditions (Mandatory)

Each phase MUST stop when **ANY** is true:

1. `action == "final"` (LLM says done)
2. `iterations >= MAX` (hard limit reached)
3. Tool returned error (execution failed)
4. Risk gate fails (safety violation)
5. Timeout reached (wallclock limit)

---

## Example: Options Trading Workflow

### Phase 1: Analysis (8 iterations max)

**Task:** "Analyze NIFTY and produce trade plan"

**Allowed Tools:**
- `dhan.instrument.find`
- `dhan.market.ltp`
- `dhan.history.intraday`
- `dhan.option.chain`
- `dhan.option.expiries`

**Output:**
```json
{
  "symbol": "NIFTY",
  "strike": 24500,
  "entry_price": 120,
  "stop_loss": 78,
  "target": 168,
  "quantity": 4,
  "rationale": "..."
}
```

### Phase 2: Validation (3 iterations max)

**Task:** "Validate trade plan against risk rules"

**Allowed Tools:**
- `dhan.funds.balance`
- `dhan.positions.list`
- `dhan.market.ltp`

**Output:**
```json
{
  "status": "approved",
  "reason": "Funds sufficient, SL set, within limits"
}
```

### Phase 3: Execution (2 iterations max)

**Task:** "Execute approved trade plan"

**Allowed Tools:**
- `dhan.super.place`
- `dhan.order.place`

**Output:**
```json
{
  "order_id": "12345",
  "status": "executed"
}
```

---

## Code Example

```ruby
# Setup
registry = Ollama::Agent::ToolRegistry.new
Ollama::Agent::Tools::DhanComplete.register_all(registry: registry)

safety_gate = Ollama::Agent::SafetyGate.new(
  rules: Ollama::Agent::SafetyGate.trading_rules(
    max_position_size: 10_000,
    require_stoploss: true,
    dry_run_only: true
  )
)

# Create phased agent
phased_agent = Ollama::Agent::PhasedAgent.new(
  client: Ollama::Client.new,
  registry: registry,
  safety_gate: safety_gate
)

# Run complete workflow
result = phased_agent.run(
  workflow: :options_trading,
  task: "Analyze NIFTY and execute trade if conditions met"
)

# Result structure
{
  workflow: :options_trading,
  phases: {
    analysis: { status: "completed", iterations: 6, ... },
    validation: { status: "approved", iterations: 2, ... },
    execution: { status: "executed", iterations: 1, ... }
  },
  final_status: "executed",
  final_output: "Order placed: 12345"
}
```

---

## Key Rules (Memorize)

1. **1 Iteration = 1 LLM Call** (not multiple tools)
2. **Loop = Controller** (your code, not Ollama)
3. **Limits = Safety** (never unbounded)
4. **Big Goals = Multiple Agents** (phase separation)
5. **Trading Agents Must Terminate** (≤3 iterations for execution)

---

## Monitoring Phase (Event-Driven)

**NOT part of the loop!**

- WebSocket-driven
- No LLM calls
- Deterministic rules
- Real-time updates

This is handled separately from the agent loop.

---

## Summary

✅ **Phase-based architecture** = Safety + Clarity
✅ **Bounded iterations** = No runaway loops
✅ **Tool filtering** = Phase-specific capabilities
✅ **Stop conditions** = Guaranteed termination
✅ **Production-safe limits** = Capital protection

