# Vyapari Options Trading: Complete Architecture Summary

## 🧠 Final Mental Model

> **Think STATE MACHINE, not "AI agent"**

This is a **capital-safe multi-agent state machine** with bounded LLM calls.

---

## 📊 Complete State Machine

```
IDLE → MARKET_ANALYSIS → PLAN_VALIDATION → ORDER_EXECUTION → POSITION_TRACK → COMPLETED
  │         │                  │                  │                │
  │         └─ NO_TRADE ───────┴──────────────────┴────────────────┘
  │         └─ Failure ────────→ REJECTED
```

### Key Rules (Memorize)

✅ **Only 3 states call LLM** (Analysis, Validation, Execution)
✅ **Only 1 state places orders** (Execution)
✅ **0 LLM calls after order placement** (Position Tracking)
✅ **Max 12 LLM calls per trade** (8 + 3 + 2 = 13 theoretical max)

---

## 🅰️ State-by-State Breakdown

### 1. IDLE STATE

- **LLM?** ❌ NO
- **Max Iterations:** 0
- **Purpose:** Wait for external trigger
- **Triggers:** Time / Signal / Webhook / Scheduled
- **Output:** → MARKET_ANALYSIS

---

### 2. MARKET ANALYSIS STATE (Agent A)

- **LLM?** ✅ YES
- **Max Iterations:** 5-8
- **Agent:** Agent A (LLM)
- **Purpose:** Understand market context and generate TradePlan

**Allowed Tools:**
- ✅ dhan.instrument.find
- ✅ dhan.market.ltp
- ✅ dhan.market.quote
- ✅ dhan.history.intraday
- ✅ dhan.history.daily
- ✅ dhan.option.chain
- ✅ dhan.option.expiries

**Blocked Tools:**
- ❌ dhan.funds.*
- ❌ dhan.order.*
- ❌ dhan.position.*

**Output:** TradePlan JSON
```json
{
  "bias": "BULLISH | BEARISH | NO_TRADE",
  "setup": "BREAKOUT | TREND | REVERSAL",
  "strike": { "security_id": "...", "type": "CE | PE" },
  "entry_logic": "text",
  "invalidation": "text"
}
```

**Stop Conditions:**
- Bias = NO_TRADE
- Iteration limit reached
- Market unclear

---

### 3. PLAN VALIDATION STATE (Agent B)

- **LLM?** ✅ YES
- **Max Iterations:** 2-3
- **Agent:** Agent B (LLM + Rules)
- **Purpose:** Convert TradePlan → ExecutablePlan OR Reject

**Allowed Tools:**
- ✅ dhan.funds.balance
- ✅ dhan.positions.list
- ✅ dhan.instrument.find

**Blocked Tools:**
- ❌ dhan.order.*
- ❌ dhan.market.*
- ❌ dhan.history.*

**Output:** APPROVED / REJECTED with ExecutablePlan

**Hard Rules:**
- No SL → reject
- Risk > allowed → reject
- Funds insufficient → reject
- **If uncertain → reject (rejection is success)**

---

### 4. ORDER EXECUTION STATE (Agent C)

- **LLM?** ✅ YES
- **Max Iterations:** 1-2
- **Agent:** Agent C (LLM, nearly dumb)
- **Purpose:** Place exactly ONE order

**Allowed Tools:**
- ✅ dhan.super.place (preferred)
- ✅ dhan.order.place (fallback)

**Blocked Tools:**
- ❌ Everything else

**Output:** order_id

**Why so strict?**
- Orders are irreversible
- Retries duplicate trades
- Fail fast → alert human

---

### 5. POSITION TRACKING STATE

- **LLM?** ❌ ABSOLUTELY NOT
- **Max Iterations:** 0
- **Agent:** Rules Engine (deterministic)
- **Purpose:** Real-time trade management

**Driven by:**
- DhanHQ WebSocket
- TickCache
- Deterministic rules

**Responsibilities:**
- Trailing SL
- Emergency exits
- Target hit
- Partial fills
- Kill switch

**Why NO LLM?**
- Latency unacceptable
- Determinism matters
- Predictability required

---

### 6. COMPLETED STATE

- **LLM?** ❌ NO
- **Max Iterations:** 0
- **Purpose:** Finalize trade lifecycle
- **Actions:** Persist journal, record metrics, reset context
- **Output:** → IDLE

---

## 📁 File Structure (Mapped to Vyapari)

```
lib/vyapari/options/
├── trading_state_machine.rb      # Formal state machine
├── phased_agent.rb               # Phase orchestrator
├── agent_prompts.rb              # Exact prompts for A, B, C
├── complete_integration.rb       # Full system integration
├── state_machine.rb              # Original state machine (legacy)
├── phased_usage_example.rb      # Usage examples
└── REFACTORING_GUIDE.md          # Migration guide
```

---

## 🔢 Production-Safe Iteration Numbers

| State             | LLM Calls | Iterations | Justification                         |
| ----------------- | --------- | ---------- | ------------------------------------- |
| **Market Analysis** | YES       | 5-8        | Discovery allowed, but must terminate |
| **Plan Validation** | YES       | 2-3        | Reject fast if uncertain              |
| **Order Execution** | YES       | 1-2        | Never loop, fail fast                 |
| **Position Track** | NO        | 0          | WebSocket only, NO LLM                |

**Hard Global Limit:** 12 LLM calls per trade
**Typical:** 9-11 calls (6-8 + 2 + 1)
**Maximum:** 13 calls (8 + 3 + 2)

---

## 🚀 Usage Example

```ruby
# Setup complete system
system = Vyapari::Options::CompleteIntegration.setup_system(dry_run: true)

# Run workflow
result = Vyapari::Options::CompleteIntegration.run_complete_workflow(
  task: "Analyze NIFTY options buying",
  dry_run: true
)

# Result includes:
# - state_machine: State transitions tracked
# - result: Phase results with iterations
# - total_llm_calls: Actual LLM calls used
```

---

## 🧨 Why This Architecture is Bulletproof

✅ **Prevents infinite loops** - Hard iteration caps
✅ **Prevents order duplication** - Execution phase is 1-2 iterations
✅ **Keeps WS path deterministic** - NO LLM in position tracking
✅ **Makes failures safe** - Rejection is success
✅ **Easy to test** - Each state is isolated
✅ **Matches institutional systems** - Not one giant "AI brain"

---

## 📋 Implementation Checklist

- [x] Formal state machine with transitions
- [x] Phase-based agent orchestrator
- [x] Exact prompts for Agent A, B, C
- [x] Output schemas for each agent
- [x] Tool filtering per phase
- [x] Iteration limits enforced
- [x] Safety gates integrated
- [x] State tracking and history
- [x] Complete integration example
- [x] Documentation and guides

---

## 🎯 Next Steps

1. **Test each phase independently** with mocked tools
2. **Run end-to-end workflow** in dry-run mode
3. **Monitor iteration counts** in production
4. **Add position tracking** (WebSocket integration)
5. **Persist trade plans** for backtesting

---

## Summary

✅ **State machine** = Clear boundaries
✅ **Bounded iterations** = No runaway loops
✅ **Tool filtering** = Phase-specific capabilities
✅ **Stop conditions** = Guaranteed termination
✅ **Production-safe limits** = Capital protection
✅ **Position tracking** = WebSocket only (NO LLM)

**Failure is not a bug — failure is a safety feature.**

This is how **real trading desks** structure automation.

