# Strike Selection Walkthrough: Real NIFTY Example

## Scenario

**Date:** 2024-01-15
**Time:** 10:30 AM IST
**Underlying:** NIFTY
**Spot Price:** 22,450
**Mode:** OPTIONS_INTRADAY

---

## Step-by-Step Walkthrough

### PHASE 1: Multi-Timeframe Analysis (Already Completed)

**HTF (15m) Analysis:**
- Regime: `TREND_DAY`
- Structure: `HH_HL` (Higher Highs, Higher Lows)
- Tradable: `true`

**MTF (5m) Analysis:**
- Direction: `BULLISH`
- Momentum: `STRONG`
- Aligned with HTF: `true`

**LTF (1m) Analysis:**
- Entry Type: `BREAKOUT`
- Trigger: "Price breaks above 22,450 with volume"
- SL Level: 22,420

---

### PHASE 2: Strike Selection (NEW)

#### Step 1: Direction → CE or PE

**Input:** MTF direction = `BULLISH`
**Decision:** `CE` (Call Options)

✅ **Result:** We're buying Call Options

---

#### Step 2: Market Regime → How Far OTM?

**Input:** HTF regime = `TREND_DAY`
**Rule:** Strong Trend/Expansion → ATM to 1 step OTM

**Decision:** Allow `ATM` or `1 step OTM`

✅ **Result:** We can consider strikes at ATM (22,450) or 1 step OTM (22,500)

---

#### Step 3: Momentum Strength → ITM vs ATM vs OTM

**Input:** MTF momentum = `STRONG`
**Rule:** STRONG momentum → ATM or slight OTM

**Decision:** Prefer `ATM` or `slight OTM`

✅ **Result:** Both ATM (22,450) and 1 OTM (22,500) are acceptable

---

#### Step 4: Volatility Filter

**Input:**
- India VIX: 14.5 (moderate)
- 15m candle expansion: Above average
- Volatility State: `expanding`

**Rule:** Expanding vol → Allow OTM

**Decision:** `allow_otm`

✅ **Result:** OTM strikes are allowed

---

#### Step 5: Time Remaining

**Input:** Current time = `10:30 AM`
**Rule:** 9:20-11:30 → ATM/1 OTM allowed

**Decision:** `atm_otm` allowed

✅ **Result:** Both ATM and 1 OTM are acceptable at this time

---

### PHASE 3: Option Chain Analysis

**Tool Call:** `dhan.option.chain`
```json
{
  "underlying_scrip": "NIFTY",
  "underlying_seg": "IDX_I",
  "expiry": "2024-01-18"
}
```

**Response:**
```json
{
  "spot_price": 22450,
  "contracts": [
    {
      "security_id": "12345",
      "strike": 22400,
      "type": "CE",
      "ltp": 125.50,
      "delta": 0.45,
      "iv": 18.5,
      "bid": 124.00,
      "ask": 127.00,
      "volume": 15000
    },
    {
      "security_id": "12346",
      "strike": 22450,
      "type": "CE",
      "ltp": 95.25,
      "delta": 0.50,
      "iv": 18.2,
      "bid": 94.00,
      "ask": 96.50,
      "volume": 25000
    },
    {
      "security_id": "12347",
      "strike": 22500,
      "type": "CE",
      "ltp": 68.75,
      "delta": 0.35,
      "iv": 18.0,
      "bid": 67.50,
      "ask": 70.00,
      "volume": 18000
    },
    {
      "security_id": "12348",
      "strike": 22550,
      "type": "CE",
      "ltp": 48.25,
      "delta": 0.25,
      "iv": 17.8,
      "bid": 47.00,
      "ask": 49.50,
      "volume": 12000
    }
  ]
}
```

---

### PHASE 4: Apply Filters

**Filter 1: Direction**
- ✅ Keep only CE contracts
- ✅ All contracts are CE

**Filter 2: Regime (TREND_DAY)**
- ✅ Allow ATM (22,450) and 1 OTM (22,500)
- ❌ Reject 22,400 (ITM, too far)
- ❌ Reject 22,550 (2 OTM, too far)

**Filter 3: Momentum (STRONG)**
- ✅ Both ATM and 1 OTM acceptable
- ✅ Prefer ATM for stronger delta

**Filter 4: Volatility (Expanding)**
- ✅ OTM allowed
- ✅ Both strikes pass

**Filter 5: Time (10:30 AM)**
- ✅ ATM/1 OTM allowed
- ✅ Both strikes pass

**Filter 6: Limit to ±1-2 strikes**
- ✅ ATM (22,450) = 0 steps from spot
- ✅ 1 OTM (22,500) = 1 step from spot
- ✅ Both within limit

---

### PHASE 5: Final Strike Candidates

**Candidate 1: ATM (22,450 CE)**
```json
{
  "security_id": "12346",
  "strike": 22450,
  "type": "CE",
  "moneyness": "ATM",
  "ltp": 95.25,
  "delta": 0.50,
  "iv": 18.2,
  "bid_ask_spread_pct": 2.6,
  "reason": "ATM strike with strong delta (0.50) and good liquidity. Premium: ₹95.25",
  "risk_note": "Higher premium but lower theta decay. Better for strong momentum continuation."
}
```

**Candidate 2: 1 OTM (22,500 CE)**
```json
{
  "security_id": "12347",
  "strike": 22500,
  "type": "CE",
  "moneyness": "OTM",
  "ltp": 68.75,
  "delta": 0.35,
  "iv": 18.0,
  "bid_ask_spread_pct": 3.6,
  "reason": "1 step OTM strike allowed by strong trend + expanding volatility. Premium: ₹68.75 (28% cheaper than ATM)",
  "risk_note": "Lower premium but needs follow-through. Suitable for expansion day with strong momentum."
}
```

---

### PHASE 6: Strike Selection Output

```json
{
  "preferred_type": "CE",
  "atm_strike": 22450,
  "candidates": [
    {
      "security_id": "12346",
      "strike": 22450,
      "type": "CE",
      "moneyness": "ATM",
      "reason": "ATM strike with strong delta (0.50) and good liquidity. Premium: ₹95.25",
      "risk_note": "Higher premium but lower theta decay. Better for strong momentum continuation."
    },
    {
      "security_id": "12347",
      "strike": 22500,
      "type": "CE",
      "moneyness": "OTM",
      "reason": "1 step OTM strike allowed by strong trend + expanding volatility. Premium: ₹68.75 (28% cheaper than ATM)",
      "risk_note": "Lower premium but needs follow-through. Suitable for expansion day with strong momentum."
    }
  ]
}
```

---

## Key Decisions Made

1. ✅ **Direction:** BULLISH → CE (from MTF analysis)
2. ✅ **Regime:** TREND_DAY → Allow 1 OTM (from HTF analysis)
3. ✅ **Momentum:** STRONG → Prefer ATM/OTM (from MTF analysis)
4. ✅ **Volatility:** Expanding → Allow OTM (from volatility filter)
5. ✅ **Time:** 10:30 AM → ATM/1 OTM allowed (from time filter)
6. ✅ **Limit:** ±1-2 strikes → Both candidates within limit

---

## What Agent A Did NOT Do

❌ Did NOT choose quantity (Agent B's job)
❌ Did NOT choose SL/TP values (Agent B's job)
❌ Did NOT optimize for "cheap premium" (structure-based, not cost-based)
❌ Did NOT decide execution timing (Agent C's job)
❌ Did NOT place orders (Agent C's job)
❌ Did NOT scan entire chain (limited to ±1-2 strikes)

---

## Why This Works

1. **Deterministic:** Same inputs → same outputs
2. **Structure-based:** Not "cheap premium" hunting
3. **Context-aware:** Uses all timeframe analyses
4. **Time-sensitive:** Respects theta decay
5. **Limited scope:** ±1-2 strikes prevents noise
6. **Safety-first:** Multiple filters prevent bad strikes

---

## Next Steps (After Agent A)

**Agent B (Validation):**
- Check funds
- Validate risk limits
- Choose final strike from candidates
- Set quantity, SL, TP

**Agent C (Execution):**
- Place order for approved strike
- Confirm execution

---

## Edge Cases Handled

### Case 1: Range Market
- **Regime:** RANGE
- **Result:** NO_TRADE (options die in ranges)
- **Why:** No directional edge

### Case 2: Weak Momentum
- **Momentum:** WEAK
- **Result:** NO_TRADE (cheap OTM is trap)
- **Why:** Weak momentum won't move OTM strikes

### Case 3: Late Session (After 2:45 PM)
- **Time:** 15:00
- **Result:** NO_NEW_TRADES
- **Why:** Theta decay too high

### Case 4: Contracting Volatility
- **Vol State:** CONTRACTING
- **Result:** NO_TRADE (no premium expansion)
- **Why:** Options need volatility expansion

---

## Summary

**Strike selection is:**
- ✅ Part of Agent A (analysis phase)
- ✅ Deterministic (rules-based)
- ✅ Structure-driven (not cost-driven)
- ✅ Limited scope (±1-2 strikes)
- ✅ Context-aware (uses all MTF analysis)
- ✅ Time-sensitive (respects theta)

**Strike selection is NOT:**
- ❌ Execution (Agent C's job)
- ❌ Risk validation (Agent B's job)
- ❌ "Cheap premium" hunting
- ❌ Entire chain scanning
- ❌ LLM hallucination

This walkthrough shows how Agent A uses market structure, momentum, volatility, and time to select strike candidates **before** Agent B validates risk and Agent C executes.

