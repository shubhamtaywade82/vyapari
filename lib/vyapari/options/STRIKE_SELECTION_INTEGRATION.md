# Strike Selection Integration Summary

## ✅ All Three Components Delivered

### A. Exact Agent A Prompt + Schema with Strike Selection

**File:** `lib/vyapari/options/agent_prompts.rb` (updated)

- ✅ Added STEP 4: Strike Selection sub-phase to Agent A prompt
- ✅ Updated output schema to include `strike_selection` object
- ✅ Enforced decision framework: Direction → Regime → Momentum → Volatility → Time
- ✅ Limited to ±1-2 strikes around ATM only
- ✅ Updated iteration budget: 7 → 9 iterations (added 2 for strike selection)

**Key Features:**
- Strike selection is MANDATORY for OPTIONS_INTRADAY mode
- Deterministic rules (not "cheap premium" hunting)
- Structure-based (uses all MTF analysis)
- Time-sensitive (respects theta decay)

---

### B. Sample NIFTY Option-Chain → Strike Selection Walkthrough

**File:** `lib/vyapari/options/STRIKE_SELECTION_WALKTHROUGH.md`

**Complete walkthrough showing:**
- Real NIFTY scenario (spot: 22,450, time: 10:30 AM)
- Step-by-step decision process:
  1. Direction → CE (from BULLISH)
  2. Regime → Allow 1 OTM (from TREND_DAY)
  3. Momentum → ATM/OTM (from STRONG)
  4. Volatility → Allow OTM (from expanding)
  5. Time → ATM/1 OTM (from 10:30 AM)
- Option chain analysis with real data
- Filter application and candidate selection
- Final output with two candidates (ATM and 1 OTM)

**Edge cases covered:**
- Range market → NO_TRADE
- Weak momentum → NO_TRADE
- Late session → NO_NEW_TRADES
- Contracting volatility → NO_TRADE

---

### C. Agent A Code Implementation with Strike Selection

**Files:**
1. `lib/vyapari/options/mtf_agent_a.rb` - Updated with strike selection phase
2. `lib/vyapari/options/strike_selection_framework.rb` - Decision framework module
3. `lib/vyapari/options/mtf_tool_plan.rb` - Updated tool plan

**Implementation Details:**

#### 1. Strike Selection Framework Module
- `strike_distance_from_regime(regime)` - Determines strike distance from market regime
- `strike_preference_from_momentum(momentum)` - Determines preference from momentum
- `strike_allowance_from_volatility(vol_state)` - Determines allowance from volatility
- `strike_allowance_from_time(current_time)` - Determines allowance from time of day
- `filter_strikes(...)` - Applies all filters to option chain candidates

#### 2. MTF Agent A Updates
- Added `analyze_strike_selection()` method
- Added strike selection phase to `run()` method
- Updated `build_synthesis_prompt()` to include strike selection
- Added extraction methods: `extract_strike_candidates()`, `extract_atm_strike()`, `extract_strike_reason()`
- Updated iteration budget: 7 → 9 iterations

#### 3. Tool Plan Updates
- Added `strike_selection` phase to `OPTIONS_INTRADAY_PLAN`
- Tools: `dhan.option.chain` and `dhan.market.ltp`
- 2 iterations for strike selection
- Updated total iterations: 7 → 9

---

## Architecture Flow

```
AGENT A (Market Analysis)
│
├─ PHASE 1: HTF Analysis (15m) - 2 iterations
│   └─ Determine regime: TREND_DAY / RANGE / EXPANSION / NO_TRADE
│
├─ PHASE 2: MTF Analysis (5m) - 2 iterations
│   └─ Determine direction & momentum (must align with HTF)
│
├─ PHASE 3: LTF Analysis (1m) - 2 iterations
│   └─ Determine entry trigger & SL (refines price only)
│
├─ PHASE 4: Strike Selection - 2 iterations (NEW)
│   ├─ Fetch option chain (±1-2 strikes around ATM)
│   ├─ Apply filters:
│   │   ├─ Direction → CE or PE
│   │   ├─ Regime → How far OTM
│   │   ├─ Momentum → ITM/ATM/OTM preference
│   │   ├─ Volatility → Allowance
│   │   └─ Time → Restriction
│   └─ Output strike candidates
│
└─ PHASE 5: Synthesis - 1 iteration
    └─ Combine all analyses into TradePlan with strike_selection

Total: 9 iterations (fits in 5-8 budget → updated to 9)
```

---

## Decision Framework (5 Steps)

### 1. Direction → CE or PE
- **Input:** MTF direction (BULLISH/BEARISH)
- **Output:** CE (for bullish) or PE (for bearish)
- **Rule:** Direct mapping from direction

### 2. Market Regime → How Far OTM?
- **Input:** HTF regime
- **Output:** `:atm`, `:one_otm`, or `:no_trade`
- **Rules:**
  - Strong Trend/Expansion → `:one_otm` (allow 1 step OTM)
  - Normal Trend → `:atm` (ATM only)
  - Range/Chop → `:no_trade` (options die in ranges)

### 3. Momentum Strength → ITM vs ATM vs OTM
- **Input:** MTF momentum
- **Output:** `:atm_otm`, `:atm`, or `:no_trade`
- **Rules:**
  - STRONG → `:atm_otm` (ATM or slight OTM)
  - MODERATE → `:atm` (ATM only)
  - WEAK → `:no_trade` (cheap OTM is trap)

### 4. Volatility Filter
- **Input:** Volatility state (expanding/average/contracting)
- **Output:** `:allow_otm`, `:atm_only`, or `:no_trade`
- **Rules:**
  - Expanding → `:allow_otm`
  - Average → `:atm_only`
  - Contracting → `:no_trade` (no premium expansion)

### 5. Time Remaining
- **Input:** Current time
- **Output:** `:atm_otm`, `:atm`, `:itm_atm`, or `:no_new_trades`
- **Rules:**
  - 9:20-11:30 → `:atm_otm` (early session)
  - 11:30-13:30 → `:atm` (mid session)
  - 13:30-14:45 → `:itm_atm` (late session, theta decay)
  - After 14:45 → `:no_new_trades` (theta too high)

---

## Safety Rules Enforced

1. ✅ **Limited scope** - ±1-2 strikes around ATM only
2. ✅ **No range trading** - Range regime → NO_TRADE
3. ✅ **No weak momentum** - Weak momentum → NO_TRADE
4. ✅ **Time-based cutoffs** - After 14:45 → NO_NEW_TRADES
5. ✅ **Volatility requirement** - Contracting vol → NO_TRADE
6. ✅ **Agent B can still reject** - All candidates subject to risk validation

---

## What Agent A Does vs. Doesn't Do

### ✅ Agent A DOES:
- Analyze market structure (MTF)
- Select strike candidates based on structure
- Apply deterministic filters
- Output candidates for Agent B

### ❌ Agent A DOES NOT:
- Choose quantity (Agent B's job)
- Choose SL/TP values (Agent B's job)
- Optimize for "cheap premium" (structure-based, not cost-based)
- Decide execution timing (Agent C's job)
- Place orders (Agent C's job)
- Scan entire chain (limited to ±1-2 strikes)

---

## Integration Points

### 1. Agent A → Agent B
- Agent A outputs `strike_selection.candidates[]`
- Agent B validates risk and selects final strike
- Agent B sets quantity, SL, TP

### 2. Agent B → Agent C
- Agent B outputs `execution_plan.security_id`
- Agent C places order for approved strike
- Agent C confirms execution

---

## Files Created/Updated

1. ✅ `lib/vyapari/options/agent_prompts.rb` - Updated prompt & schema
2. ✅ `lib/vyapari/options/mtf_agent_a.rb` - Added strike selection phase
3. ✅ `lib/vyapari/options/strike_selection_framework.rb` - Decision framework
4. ✅ `lib/vyapari/options/mtf_tool_plan.rb` - Updated tool plan
5. ✅ `lib/vyapari/options/STRIKE_SELECTION_WALKTHROUGH.md` - Walkthrough
6. ✅ `lib/vyapari/options/STRIKE_SELECTION_INTEGRATION.md` - This file

---

## Iteration Budget

| Phase | Iterations | Notes |
|-------|------------|-------|
| HTF Analysis | 2 | Regime determination |
| MTF Analysis | 2 | Direction & momentum |
| LTF Analysis | 2 | Entry trigger |
| **Strike Selection** | **2** | **NEW: Strike candidates** |
| Synthesis | 1 | Final TradePlan |
| **Total** | **9** | **Updated from 7** |

**Note:** Budget increased from 7 to 9 iterations to accommodate strike selection. Still within reasonable bounds for analysis phase.

---

## Key Benefits

✅ **Deterministic** - Same inputs → same outputs
✅ **Structure-based** - Not "cheap premium" hunting
✅ **Context-aware** - Uses all MTF analysis
✅ **Time-sensitive** - Respects theta decay
✅ **Limited scope** - ±1-2 strikes prevents noise
✅ **Safety-first** - Multiple filters prevent bad strikes
✅ **Separation of concerns** - Analysis vs. Validation vs. Execution

---

## Summary

**Strike selection is now:**
- ✅ Part of Agent A (analysis phase)
- ✅ Deterministic (rules-based framework)
- ✅ Structure-driven (not cost-driven)
- ✅ Limited scope (±1-2 strikes)
- ✅ Context-aware (uses all MTF analysis)
- ✅ Time-sensitive (respects theta)
- ✅ Fully integrated into MTF Agent A

**This prevents:**
- ❌ LLM hallucination of strikes
- ❌ "Cheap premium" hunting
- ❌ Entire chain scanning
- ❌ Execution-time strike selection
- ❌ Inconsistent strike logic

**The system now follows the correct flow:**
1. **Agent A proposes** (market analysis + strike candidates)
2. **Agent B approves** (risk validation + final strike selection)
3. **Agent C executes** (order placement)

This is **capital-safe architecture** for options trading.

