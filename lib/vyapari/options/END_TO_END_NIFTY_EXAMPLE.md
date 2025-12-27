# End-to-End NIFTY Options Trading Example

## Scenario

**Date:** 2024-01-15
**Time:** 10:30 AM IST
**Underlying:** NIFTY
**Spot Price:** 22,450
**Account Balance:** ₹1,00,000
**Max Risk Per Trade:** 1% (₹1,000)

---

## PHASE 1: Agent A (Market Analysis)

### Input
```
Task: "Analyze NIFTY options buying opportunity"
```

### Agent A Output (TradePlan)

```json
{
  "mode": "OPTIONS_INTRADAY",
  "htf": {
    "timeframe": "15m",
    "regime": "TREND_DAY",
    "tradable": true
  },
  "mtf": {
    "timeframe": "5m",
    "direction": "BULLISH",
    "momentum": "STRONG"
  },
  "ltf": {
    "timeframe": "1m",
    "entry_type": "BREAKOUT",
    "trigger": "Price breaks above 22,450 with volume"
  },
  "bias": "BULLISH",
  "strike_bias": "CE",
  "strike_selection": {
    "preferred_type": "CE",
    "atm_strike": 22450,
    "candidates": [
      {
        "security_id": "12346",
        "strike": 22450,
        "type": "CE",
        "moneyness": "ATM",
        "reason": "ATM strike with strong delta (0.50) and good liquidity",
        "risk_note": "Higher premium but lower theta decay"
      },
      {
        "security_id": "12347",
        "strike": 22500,
        "type": "CE",
        "moneyness": "OTM",
        "reason": "1 step OTM strike allowed by strong trend + expanding volatility",
        "risk_note": "Lower premium but needs follow-through"
      }
    ]
  },
  "stop_loss_logic": "1m candle close below last higher low (approximately 22,420 level)",
  "take_profit_logic": "15m range high + expansion (targeting previous day high around 22,550)",
  "invalidations": [
    "15m candle closes back inside range",
    "5m momentum weakens below VWAP"
  ]
}
```

### Key Points from Agent A

✅ **Strike candidates:** 2 options (ATM 22,450 CE and 1 OTM 22,500 CE)
✅ **SL logic:** Structural ("1m candle close below last higher low")
✅ **TP logic:** Market-based ("15m range high + expansion")
❌ **NO quantity** (Agent B's job)
❌ **NO numeric SL/TP** (Agent B's job)

---

## PHASE 2: Agent B (Risk Validation)

### Step 1: Get Current Option LTP

**Tool Call:** `dhan.market.ltp`
```json
{
  "exchange_segment": "NSE_FNO",
  "product_type": "INTRADAY",
  "security_id": "12346"
}
```

**Response:**
```json
{
  "ltp": 95.25,
  "timestamp": "2024-01-15T10:30:00+05:30"
}
```

**Selected Strike:** ATM 22,450 CE (security_id: 12346)
**Current LTP:** ₹95.25

---

### Step 2: Get Funds Balance

**Tool Call:** `dhan.funds.balance`

**Response:**
```json
{
  "available_margin": 85000,
  "utilized_margin": 15000,
  "total_margin": 100000
}
```

**Available Funds:** ₹85,000

---

### Step 3: Convert SL Logic to Numeric Price

**Input:**
- SL Logic: "1m candle close below last higher low (approximately 22,420 level)"
- Option LTP: ₹95.25
- Underlying Spot: 22,450

**Risk Calculator:**
```ruby
calculator = RiskCalculator.new(
  account_balance: 100000,
  max_risk_percent: 1.0,
  instrument: "NIFTY"
)

sl_result = calculator.convert_sl_logic_to_price(
  sl_logic: "1m candle close below last higher low (approximately 22,420 level)",
  option_ltp: 95.25,
  underlying_spot: 22450
)
```

**Output:**
```json
{
  "sl_price": 70.00,
  "sl_percent": 0.265,
  "status": "approved",
  "reason": "Converted SL logic to price: ₹70.00 (26.5% SL)"
}
```

**SL Price:** ₹70.00 (26.5% SL - within 30% cap for NIFTY)

---

### Step 4: Convert TP Logic to Numeric Prices

**Input:**
- TP Logic: "15m range high + expansion (targeting previous day high around 22,550)"
- Entry Price: ₹95.25
- Stop Loss: ₹70.00
- Risk: ₹95.25 - ₹70.00 = ₹25.25

**Risk Calculator:**
```ruby
tp_result = calculator.convert_tp_logic_to_prices(
  tp_logic: "15m range high + expansion (targeting previous day high around 22,550)",
  entry_price: 95.25,
  stop_loss_price: 70.00,
  underlying_spot: 22450,
  previous_day_high: 22550
)
```

**Output:**
```json
{
  "partial": {
    "price": 125.50,
    "rr": 1.2,
    "exit_pct": 50
  },
  "final": {
    "price": 145.75,
    "rr": 2.0,
    "exit_pct": 50
  },
  "status": "approved",
  "reason": "Converted TP logic to prices: Partial ₹125.50 (1.2x RR), Final ₹145.75 (2.0x RR)"
}
```

**TP Prices:**
- Partial: ₹125.50 (1.2x RR, exit 50%)
- Final: ₹145.75 (2.0x RR, exit 50%)

---

### Step 5: Calculate Lot Size

**Input:**
- Entry Price: ₹95.25
- Stop Loss: ₹70.00
- Risk per lot: (95.25 - 70.00) × 75 = ₹1,893.75
- Max risk per trade: ₹1,000 (1% of ₹1,00,000)

**Risk Calculator:**
```ruby
lot_result = calculator.calculate_lot_size(
  entry_price: 95.25,
  stop_loss_price: 70.00
)
```

**Output:**
```json
{
  "lots": 0,
  "risk_per_lot": 1893.75,
  "total_risk": 1893.75,
  "status": "rejected",
  "reason": "Risk per lot (₹1,893.75) exceeds max risk per trade (₹1,000)"
}
```

**Result:** ❌ **TRADE REJECTED**

**Reason:** Risk per lot (₹1,893.75) exceeds maximum risk per trade (₹1,000)

---

## Alternative Scenario: Lower SL (Approved Trade)

### Revised SL Logic

**Agent A provides:** "1m candle close below VWAP (approximately 22,430 level)"

**Risk Calculator converts:**
- SL Price: ₹80.00 (16% SL)
- Risk per lot: (95.25 - 80.00) × 75 = ₹1,143.75

**Still exceeds max risk!**

---

### Further Revised: Tighter SL

**Agent A provides:** "1m candle close below entry trigger level (approximately 22,440 level)"

**Risk Calculator converts:**
- SL Price: ₹85.00 (10.7% SL)
- Risk per lot: (95.25 - 85.00) × 75 = ₹768.75

**Lot Calculation:**
- Allowed lots: floor(₹1,000 / ₹768.75) = 1 lot
- Total risk: 1 × ₹768.75 = ₹768.75 ✅

**Result:** ✅ **TRADE APPROVED**

---

### Agent B Final Output (ExecutablePlan)

```json
{
  "status": "APPROVED",
  "reason": "Trade plan validated successfully. Risk per lot ₹768.75 within limits.",
  "execution_plan": {
    "quantity": 75,
    "lots": 1,
    "entry_price": 95.25,
    "stop_loss": 85.00,
    "take_profit": {
      "partial": {
        "price": 110.50,
        "rr": 1.2,
        "exit_pct": 50
      },
      "final": {
        "price": 130.75,
        "rr": 2.0,
        "exit_pct": 50
      }
    },
    "order_type": "SUPER",
    "security_id": "12346",
    "total_risk": 768.75
  }
}
```

**Key Points:**
- ✅ Quantity: 75 (1 lot × 75)
- ✅ Lots: 1 (within max 6 lots)
- ✅ SL: ₹85.00 (10.7% - within 30% cap)
- ✅ TP: Partial ₹110.50 (1.2x RR), Final ₹130.75 (2.0x RR)
- ✅ Total Risk: ₹768.75 (within ₹1,000 limit)

---

## PHASE 3: Agent C (Order Execution)

### Input
```json
{
  "quantity": 75,
  "entry_price": 95.25,
  "stop_loss": 85.00,
  "take_profit": {
    "partial": { "price": 110.50, "exit_pct": 50 },
    "final": { "price": 130.75, "exit_pct": 50 }
  },
  "order_type": "SUPER",
  "security_id": "12346"
}
```

### Tool Call: `dhan.super.place`

```json
{
  "security_id": "12346",
  "exchange_segment": "NSE_FNO",
  "product_type": "INTRADAY",
  "transaction_type": "BUY",
  "quantity": 75,
  "order_type": "MARKET",
  "product_type": "INTRADAY",
  "stop_loss": 85.00,
  "target": 130.75
}
```

### Response

```json
{
  "order_id": "112111182198",
  "status": "PLACED",
  "message": "Super Order placed successfully"
}
```

**Order ID:** 112111182198
**Status:** PLACED ✅

---

## Summary: What Each Agent Did

### Agent A (Analysis)
- ✅ Analyzed market structure (MTF)
- ✅ Selected strike candidates (ATM 22,450 CE)
- ✅ Provided SL logic (structural)
- ✅ Provided TP logic (market-based)
- ❌ Did NOT choose quantity
- ❌ Did NOT provide numeric SL/TP

### Agent B (Validation)
- ✅ Converted SL logic → ₹85.00 (10.7% SL)
- ✅ Converted TP logic → ₹110.50 partial, ₹130.75 final
- ✅ Calculated lot size → 1 lot (75 quantity)
- ✅ Validated risk → ₹768.75 (within limits)
- ✅ Validated funds → Sufficient
- ✅ Produced ExecutablePlan

### Agent C (Execution)
- ✅ Placed Super Order
- ✅ Confirmed execution (Order ID: 112111182198)
- ❌ Did NOT analyze or validate

---

## Key Learnings

1. **Agent A rejection is GOOD** - If SL is too wide, trade gets rejected early
2. **Agent B is paranoid** - Risk per lot exceeded → REJECTED
3. **Tighter SL required** - Had to reduce SL from 26.5% to 10.7% to fit risk
4. **Lot size is deterministic** - Based on risk, not "confidence"
5. **Separation works** - Each agent has clear responsibility

---

## Edge Cases Handled

### Case 1: SL Too Wide
- **SL:** 26.5% → Risk per lot: ₹1,893.75
- **Result:** REJECTED (exceeds max risk)
- **Solution:** Tighter SL required

### Case 2: Insufficient Funds
- **Required:** ₹95.25 × 75 × 2 = ₹14,287.50
- **Available:** ₹10,000
- **Result:** REJECTED (insufficient funds)

### Case 3: Max Lots Cap
- **Calculated:** 10 lots
- **Capped at:** 6 lots (hard limit)
- **Result:** Approved with 6 lots

---

## Final Architecture

```
Agent A → TradePlan (logic, not numbers)
    ↓
Agent B → ExecutablePlan (numbers, risk-validated)
    ↓
Agent C → Order ID (execution only)
```

**This is capital-safe architecture.**

