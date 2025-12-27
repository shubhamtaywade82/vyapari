# Risk Management Integration Summary

## ✅ All Three Components Delivered

### A. Exact Agent B Schema + Risk Formulas

**File:** `lib/vyapari/options/agent_prompts.rb` (updated)

- ✅ Updated Agent B prompt with risk calculation instructions
- ✅ Updated Agent B output schema with lot size, SL/TP conversion
- ✅ Clear separation: Agent A provides logic, Agent B converts to numbers

**Key Features:**
- Lot size calculation: `allowed_lots = floor(max_risk_per_trade / risk_per_lot)`
- SL conversion: Logical SL → Numeric SL price (with caps)
- TP conversion: Market-based TP → Numeric TP prices (partial + final)
- Hard caps: NIFTY 30% SL, SENSEX 25% SL, Max 6 lots

---

### B. End-to-End NIFTY Example

**File:** `lib/vyapari/options/END_TO_END_NIFTY_EXAMPLE.md`

**Complete walkthrough showing:**
- Agent A output (TradePlan with SL/TP logic)
- Agent B validation process (step-by-step)
- Risk calculation examples
- Trade rejection scenario (SL too wide)
- Trade approval scenario (tighter SL)
- Agent C execution

**Key Scenarios:**
- ❌ Rejected: SL 26.5% → Risk per lot ₹1,893.75 (exceeds ₹1,000)
- ✅ Approved: SL 10.7% → Risk per lot ₹768.75 (within limits)
- Final: 1 lot (75 quantity), Total risk ₹768.75

---

### C. Agent B Implementation in Ruby

**File:** `lib/vyapari/options/risk_calculator.rb`

**Complete RiskCalculator class with:**

#### 1. Lot Size Calculation
```ruby
calculate_lot_size(entry_price:, stop_loss_price:)
```
- Calculates risk per lot: `(entry_price - stop_loss_price) × lot_size`
- Calculates allowed lots: `floor(max_risk_per_trade / risk_per_lot)`
- Hard caps: Max 6 lots, Min 1 lot
- Returns: `{ lots, risk_per_lot, total_risk, status, reason }`

#### 2. SL Logic Conversion
```ruby
convert_sl_logic_to_price(sl_logic:, option_ltp:, underlying_spot:, recent_swing_low:)
```
- Converts structural SL logic → numeric SL price
- Validates against max SL caps (NIFTY 30%, SENSEX 25%)
- Returns: `{ sl_price, sl_percent, status, reason }`

#### 3. TP Logic Conversion
```ruby
convert_tp_logic_to_prices(tp_logic:, entry_price:, stop_loss_price:, underlying_spot:, previous_day_high:)
```
- Converts market-based TP logic → numeric TP prices
- Calculates partial (1.2x RR) and final (2.0x RR) targets
- Validates minimum RR ratios
- Returns: `{ partial: { price, rr, exit_pct }, final: { price, rr, exit_pct }, status, reason }`

#### 4. Complete Trade Plan Validation
```ruby
validate_trade_plan(trade_plan:, option_ltp:, funds_available:)
```
- Validates complete trade plan end-to-end
- Converts SL/TP, calculates lot size, checks funds
- Returns: `{ status, sl_price, tp_partial, tp_final, lots, quantity, total_risk, required_margin, reason }`

---

## Ownership Map (Final)

| Decision | Agent | Why |
|----------|-------|-----|
| **Direction & regime** | Agent A | Market interpretation |
| **Strike selection** | Agent A | Contextual, qualitative |
| **SL logic (structural)** | Agent A | Market-aware, not money-aware |
| **TP logic (market-based)** | Agent A | Market-aware, not money-aware |
| **SL price (numeric)** | Agent B | Risk-based, with caps |
| **TP prices (numeric)** | Agent B | Risk-reward validated |
| **Lot size / quantity** | Agent B | Pure math + capital |
| **Order placement** | Agent C | Mechanical only |

---

## Risk Formulas (Production-Ready)

### Lot Size Calculation
```ruby
max_risk_per_trade = account_balance × (max_risk_percent / 100)
risk_per_lot = (entry_price - stop_loss_price) × lot_size
allowed_lots = floor(max_risk_per_trade / risk_per_lot)
final_lots = min(allowed_lots, MAX_LOTS_PER_TRADE) # Cap at 6
```

### SL Conversion
```ruby
sl_price = convert_logic_to_price(sl_logic, option_ltp)
sl_percent = ((option_ltp - sl_price) / option_ltp).abs
if sl_percent > MAX_SL_PERCENT → REJECT
```

### TP Conversion
```ruby
risk = (entry_price - stop_loss_price).abs
partial_price = entry_price + (risk × 1.2) # 1.2x RR
final_price = entry_price + (risk × 2.0)     # 2.0x RR
if partial_rr < 1.2 or final_rr < 2.0 → REJECT
```

---

## Constants (Hard-Coded)

### Lot Sizes
- NIFTY: 75
- SENSEX: 20
- BANKNIFTY: 15
- FINNIFTY: 50

### Max SL Percentages
- NIFTY: 30%
- SENSEX: 25%
- BANKNIFTY: 30%
- FINNIFTY: 30%

### Other Limits
- Max lots per trade: 6
- Min risk-reward: 1.5x (partial 1.2x, final 2.0x)
- Default max risk: 0.5% to 1% of capital

---

## Integration Points

### Agent A → Agent B
```ruby
# Agent A outputs
{
  stop_loss_logic: "1m candle close below last higher low",
  take_profit_logic: "15m range high + expansion",
  strike_selection: { candidates: [...] }
}

# Agent B converts
risk_calc = RiskCalculator.new(account_balance: 100000, max_risk_percent: 1.0)
validation = risk_calc.validate_trade_plan(
  trade_plan: agent_a_output,
  option_ltp: 95.25,
  funds_available: 85000
)
```

### Agent B → Agent C
```ruby
# Agent B outputs
{
  status: "APPROVED",
  execution_plan: {
    quantity: 75,
    lots: 1,
    entry_price: 95.25,
    stop_loss: 85.00,
    take_profit: { partial: {...}, final: {...} },
    security_id: "12346"
  }
}

# Agent C executes
dhan.super.place(execution_plan)
```

---

## Safety Rules Enforced

1. ✅ **SL caps** - NIFTY 30%, SENSEX 25% (hard limits)
2. ✅ **Lot size limits** - Max 6 lots, Min 1 lot
3. ✅ **Risk limits** - Max 0.5-1% per trade
4. ✅ **RR validation** - Min 1.2x partial, 2.0x final
5. ✅ **Funds check** - Required margin must be available
6. ✅ **Rejection is success** - Better to reject than lose capital

---

## Files Created/Updated

1. ✅ `lib/vyapari/options/agent_prompts.rb` - Updated Agent A/B schemas
2. ✅ `lib/vyapari/options/risk_calculator.rb` - Complete risk calculation module
3. ✅ `lib/vyapari/options/END_TO_END_NIFTY_EXAMPLE.md` - Complete walkthrough
4. ✅ `lib/vyapari/options/RISK_MANAGEMENT_INTEGRATION.md` - This file

---

## Verification

All components tested and working:
- ✅ RiskCalculator loads successfully
- ✅ Lot size calculation: 1 lot, ₹768.75 risk (approved)
- ✅ SL conversion: Works with logic strings
- ✅ TP conversion: Works with market-based logic
- ✅ Trade plan validation: End-to-end validation

---

## Summary

**Separation of concerns achieved:**
- ✅ Agent A: Market analysis + logic (no numbers)
- ✅ Agent B: Risk calculation + validation (numbers only)
- ✅ Agent C: Execution (mechanical only)

**This prevents:**
- ❌ LLM sizing positions emotionally
- ❌ SL tied to hope instead of structure
- ❌ Quantity exceeding risk
- ❌ Bad trades getting through

**This is capital-safe architecture for options trading.**

