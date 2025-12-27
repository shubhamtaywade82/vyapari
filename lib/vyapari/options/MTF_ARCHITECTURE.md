# Multi-Timeframe Analysis Architecture

## Core Rule (Non-Negotiable)

> **Agent A does NOT "freely analyze charts".
> It performs a FIXED, ORDERED, TOP-DOWN MTF PASS.**

**No backtracking. No re-thinking lower TFs after higher TFs are decided.**

---

## Two Distinct Modes

| Mode               | Purpose              | Timeframes    |
| ------------------ | -------------------- | ------------- |
| `OPTIONS_INTRADAY` | Momentum + expansion | 15m → 5m → 1m |
| `SWING_TRADING`    | Structure + trend    | 1D → 1H → 15m |

**They are NOT interchangeable.**

---

## Options Buying — Multi-Timeframe Logic (15m / 5m / 1m)

### Order Matters (DO NOT REVERSE)

#### 🔹 TF1 — 15m (STRUCTURE & REGIME)

**Question:** *Is this a tradable market?*

Agent must decide **one and only one**:

- TREND_DAY
- RANGE / CHOP
- VOLATILITY_EXPANSION
- NO_TRADE

**Inputs:**
- 15m OHLC
- VWAP
- Range expansion
- Previous day high/low

**Tools:**
- `dhan.instrument.find` (find instrument)
- `dhan.history.intraday` (interval=15)

**Iterations:** 2

❌ **If result = `NO_TRADE` → STOP ENTIRE AGENT**
(No lower TF analysis allowed)

---

#### 🔹 TF2 — 5m (DIRECTION & MOMENTUM)

**Question:** *Which side has control?*

Agent determines:

- Direction: BULLISH / BEARISH / NEUTRAL
- Momentum: STRONG / WEAK
- Pullback vs breakout context

**Tools:**
- `dhan.history.intraday` (interval=5)
- `dhan.market.ltp` (current price)

**Iterations:** 2

**Hard Rule:**
> 5m direction must **agree** with 15m regime
> If it doesn't → NO_TRADE

---

#### 🔹 TF3 — 1m (ENTRY TRIGGER)

**Question:** *Where exactly do we enter?*

Used ONLY for:

- Entry candle
- SL placement logic
- Immediate invalidation

**Tools:**
- `dhan.history.intraday` (interval=1)
- `dhan.option.chain` (strike selection)

**Iterations:** 2

❌ **1m is NOT allowed to change bias**
❌ **1m is NOT allowed to override higher TFs**

---

#### 🔹 Synthesis (FINAL TRADE PLAN)

**Purpose:** Combine all three timeframes into final TradePlan

**Iterations:** 1

**Output:** Complete TradePlan JSON

---

## Options Agent A Output (Final)

```json
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
  "invalidations": ["condition1", "condition2"]
}
```

---

## Swing Trading — Multi-Timeframe Logic (1D / 1H / 15m)

### Order Is Different (Longer Horizon)

#### 🔹 TF1 — 1D (PRIMARY TREND)

**Question:** *Is this stock worth holding for days/weeks?*

Decisions:

- Trend: UP / DOWN / SIDEWAYS
- Structure: HH-HL / LH-LL / RANGE
- Location: Near support / resistance / breakout

**Tools:**
- `dhan.instrument.find` (find stock)
- `dhan.history.daily` (daily OHLC)

**Iterations:** 2

❌ **If daily trend = SIDEWAYS → STOP**

---

#### 🔹 TF2 — 1H (SETUP FORMATION)

**Question:** *Is a setup forming inside the trend?*

Look for:

- Pullback
- Base formation
- Compression
- Breakout structure

**Tools:**
- `dhan.history.intraday` (interval=60)

**Iterations:** 2

❌ **If no clean setup → STOP**

---

#### 🔹 TF3 — 15m (ENTRY ZONE)

**Question:** *Where exactly do we enter with defined risk?*

Used for:

- Entry zone
- Initial SL
- Invalidation

**Tools:**
- `dhan.history.intraday` (interval=15)

**Iterations:** 2

> **Lower TF cannot override higher TF**

---

## Iteration Budget — Updated

### Options Mode

- 15m analysis → 2 iterations
- 5m analysis → 2 iterations
- 1m trigger → 2 iterations
- Final synthesis → 1 iteration

👉 **Total: 7 iterations**

---

### Swing Mode

- 1D trend → 2 iterations
- 1H setup → 2 iterations
- 15m entry → 2 iterations
- Final synthesis → 1 iteration

👉 **Total: 7 iterations**

**Fits perfectly inside the 5-8 iteration budget.**

---

## Critical Safety Rules (DO NOT BREAK)

1. **Lower TF cannot override higher TF**
2. **Any TF disagreement → NO_TRADE**
3. **Entry TF only refines price, never bias**
4. **Mode (Options vs Swing) must be explicit**
5. **Agent A NEVER places orders**

---

## Tool Calling Sequence

### Options Intraday Mode

```
HTF_15M (2 iterations):
  1. dhan.instrument.find → Find NIFTY
  2. dhan.history.intraday (interval=15) → Fetch 15m OHLC
  → Determine regime: TREND_DAY / RANGE / NO_TRADE

MTF_5M (2 iterations):
  1. dhan.history.intraday (interval=5) → Fetch 5m OHLC
  2. dhan.market.ltp → Get current LTP
  → Determine direction: BULLISH / BEARISH (must align with 15m)

LTF_1M (2 iterations):
  1. dhan.history.intraday (interval=1) → Fetch 1m OHLC
  2. dhan.option.chain → Get option chain
  → Determine entry trigger and SL (refines price only)

SYNTHESIS (1 iteration):
  → Combine all timeframes into TradePlan
```

---

## Why This Solves the Problem

✅ **No TF contradictions** - Fixed order prevents conflicts
✅ **No infinite "rechecking"** - Each TF analyzed once
✅ **Clear early exits** - NO_TRADE stops immediately
✅ **Reusable for automation** - Deterministic flow
✅ **Matches real discretionary traders** - Top-down thinking

---

## Implementation Files

1. **`lib/vyapari/options/mtf_agent_a.rb`**
   - Complete MTF Agent A implementation
   - Handles both Options and Swing modes
   - Enforces fixed order and alignment rules

2. **`lib/vyapari/options/mtf_tool_plan.rb`**
   - Tool calling sequences per timeframe
   - Visual representation of tool plan
   - Iteration budget tracking

3. **Updated `agent_prompts.rb`**
   - MTF-aware system prompt
   - Updated output schema with MTF structure

4. **Updated `phased_agent.rb`**
   - Integrates MTF Agent A
   - Extracts MTF trade plan

---

## Usage

```ruby
# Create MTF Agent A
mtf_agent = Vyapari::Options::MTFAgentA.new(
  client: Ollama::Client.new,
  registry: registry,
  mode: :options_intraday
)

# Run MTF analysis
result = mtf_agent.run("Analyze NIFTY options buying")

# Result includes:
# - mode: :options_intraday
# - timeframes: { htf: {...}, mtf: {...}, ltf: {...} }
# - trade_plan: {...}
# - status: "completed" | "no_trade"
# - iterations_used: 7
```

---

## Summary

✅ **Fixed order** = No contradictions
✅ **Top-down pass** = No backtracking
✅ **Early exits** = NO_TRADE stops immediately
✅ **Alignment checks** = Lower TF must agree with higher TF
✅ **7 iterations** = Fits in 5-8 budget
✅ **Two modes** = Options vs Swing (not interchangeable)

This architecture prevents the agent from contradicting itself or looping forever.

