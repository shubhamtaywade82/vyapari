# Options Buying Strategy - Integration Research

## Executive Summary

This document maps the **₹10+ premium options buying strategy** to the existing Vyapari codebase, identifying what exists, what needs to be built, and how to integrate the three core components:

1. **PreTradeGate** - Boolean checklist (blocks weak trades)
2. **ExpansionScorer** - Probability scorer (0-100)
3. **LotSizer** - Dynamic lot sizing (1-4 lots)

---

## Current Codebase Analysis

### ✅ What Already Exists

#### 1. **Structure Analysis** (`lib/vyapari/tools/analyze_structure_15m.rb`)
- ✅ Detects HH/HL (bullish) and LL/LH (bearish)
- ✅ Returns `range` for invalid structures
- ✅ Uses EMA20 for confirmation
- **Gap**: Doesn't detect BOS with displacement, trap failures, or range expansion

#### 2. **Trend Analysis** (`lib/vyapari/tools/analyze_trend.rb`)
- ✅ Calculates RSI, ADX, EMA (9/21)
- ✅ Volume indicators (MFI, CMF, OBV)
- ✅ Returns `bullish`, `bearish`, or `avoid`
- **Gap**: Doesn't classify day type (TREND, TRAP_RESOLUTION, RANGE_EXPANSION)

#### 3. **Technical Indicators** (`lib/vyapari/indicators/`)
- ✅ ATR calculation available via `TechnicalAnalysisAdapter.atr(period: 14)`
- ✅ RSI, ADX, EMA implementations
- ✅ Volume indicators (MFI, CMF, OBV)
- **Gap**: No ATR expansion detection, no session ATR median calculation

#### 4. **Option Chain Fetching** (`lib/vyapari/tools/fetch_option_chain.rb`)
- ✅ Fetches option chain data
- ✅ Selects ATM and OTM strikes
- ✅ Returns contracts with delta, premium, spread
- **Gap**: Doesn't validate strike quality (delta range, spread %)

#### 5. **Risk Management** (`lib/trading/risk.rb`)
- ✅ Position sizing calculation
- **Gap**: No lot scaling logic, no daily loss cap tracking

---

## What Needs to Be Built

### 1. **PreTradeGate** (`lib/vyapari/options/pre_trade_gate.rb`)

**Purpose**: Boolean checklist that blocks trades if ANY condition fails.

**Required Checks**:

#### A. Market Regime Gate
```ruby
# Need to classify day type
day_type ∈ { :trend, :trap_resolution, :range_expansion }
```

**Implementation Requirements**:
- Analyze 15m structure for HH/HL or LL/LH (exists)
- Detect trap patterns (fake break + reclaim + displacement) - **NEW**
- Detect range expansion (ATR < median → sudden large candle) - **NEW**
- Reject: inside day, narrow range day - **NEW**

#### B. Time Window Gate
```ruby
# Current time validation
current_time ∈ [10:30-13:00] OR [13:45-14:30]
```

**Implementation**: Simple time check - **EASY**

#### C. Structure Gate
```ruby
# Enhanced structure detection
structure_signal ∈ {
  :bos_with_displacement,
  :trap_failure_retest,
  :range_break_with_follow_through
}
```

**Requirements**:
- Candle body > 60% - **NEW**
- Close outside prior structure - **NEW**
- Follow-through within 1-2 candles - **NEW**

#### D. Volatility Gate
```ruby
# ATR expansion check
current_ATR >= session_ATR_median
AND
ATR_slope > 0
```

**Requirements**:
- Calculate session ATR median - **NEW**
- Calculate ATR slope - **NEW**
- Use existing `TechnicalAnalysisAdapter.atr()` - **EXISTS**

#### E. Momentum Timing Gate
```ruby
# Predictive momentum check
expected_early_move ≥ ₹4 premium within 2 candles
```

**Requirements**:
- Calculate expected index move - **NEW**
- Calculate expected premium (index_move × delta) - **NEW**
- Historical momentum analysis - **NEW**

#### F. Strike Quality Gate
```ruby
# Option contract validation
delta ∈ [0.40, 0.55]
AND
spread_pct < 1%
AND
strike_distance ≤ ±1 ATM
```

**Requirements**:
- Extract delta from option chain - **EXISTS** (in contracts)
- Calculate spread % - **NEW**
- Validate strike distance - **EXISTS** (ATM calculation exists)

#### G. Expected Move Gate
```ruby
# Minimum expected premium check
(expected_index_move_points × delta) ≥ 12
```

**Requirements**:
- Calculate expected index move - **NEW**
- Use delta from option chain - **EXISTS**

#### H. Risk Feasibility Gate
```ruby
# Risk management check
max_loss_per_trade ≤ 1.5 × expected_avg_win
```

**Requirements**:
- Calculate max loss - **NEW**
- Expected win calculation - **NEW**
- Daily loss cap tracking - **NEW**

---

### 2. **ExpansionScorer** (`lib/vyapari/options/expansion_scorer.rb`)

**Purpose**: 0-100 score for trade quality (confidence, not permission).

**Scoring Components**:

| Component              | Weight | Current Status                                  |
| ---------------------- | ------ | ----------------------------------------------- |
| Structure Quality      | 0-30   | Partial (need BOS displacement, trap detection) |
| Volatility Expansion   | 0-20   | Need ATR expansion detection                    |
| Momentum Quality       | 0-15   | Need body % and follow-through analysis         |
| Time Advantage         | 0-10   | Easy (time window check)                        |
| Strike Responsiveness  | 0-10   | Need delta/spread validation                    |
| Trap/Liquidity Context | 0-10   | Need trap detection                             |
| Expected Move Buffer   | 0-5    | Need expected move calculation                  |

**Total**: 0-100 score

**Score Interpretation**:
- <50: NO TRADE
- 50-65: Small size (1 lot)
- 65-80: Standard (2 lots)
- 75-85: Aggressive (3 lots)
- ≥85: Maximum (4 lots)

---

### 3. **LotSizer** (`lib/vyapari/options/lot_sizer.rb`)

**Purpose**: Dynamic lot sizing based on expansion score.

**Logic**:
```ruby
score < 50        → 0 lots (blocked)
50 ≤ score < 65   → 1 lot
65 ≤ score < 75   → 2 lots
75 ≤ score < 85   → 3 lots
score ≥ 85        → 4 lots
```

**Additional Constraint**:
```ruby
max_loss_with_size ≤ daily_loss_cap_remaining
```

**Requirements**:
- Daily loss cap tracking - **NEW**
- Position size calculation - **EXISTS** (`Trading::Risk.position_size`)
- Risk per lot calculation - **NEW**

---

## Integration Architecture

### Proposed File Structure

```
lib/vyapari/options/
├── agent.rb                    # Existing - orchestrates workflow
├── pre_trade_gate.rb          # NEW - Boolean checklist
├── expansion_scorer.rb        # NEW - 0-100 scoring
├── lot_sizer.rb               # NEW - Dynamic lot sizing
├── day_type_classifier.rb     # NEW - Classifies day type
├── structure_analyzer.rb      # NEW - Enhanced structure detection
├── volatility_analyzer.rb     # NEW - ATR expansion analysis
└── momentum_analyzer.rb       # NEW - Momentum timing

lib/vyapari/tools/
├── analyze_structure_15m.rb   # Existing - enhance for BOS/trap detection
├── analyze_trend.rb            # Existing - enhance for day type
├── fetch_option_chain.rb      # Existing - add strike quality validation
└── recommend_trade.rb         # Existing - integrate gates/scorer/sizer

lib/vyapari/indicators/
├── technical_analysis_adapter.rb  # Existing - has ATR
└── atr_expansion.rb               # NEW - ATR expansion detection

lib/vyapari/trading/
├── risk.rb                    # Existing - enhance for lot sizing
└── daily_loss_tracker.rb     # NEW - Daily loss cap tracking
```

---

## Implementation Priority

### Phase 1: Core Gates (Block Weak Trades)
1. **Time Window Gate** - Easiest, immediate value
2. **Strike Quality Gate** - Uses existing option chain data
3. **Expected Move Gate** - Core requirement
4. **Risk Feasibility Gate** - Prevents over-sizing

### Phase 2: Enhanced Analysis
5. **Day Type Classifier** - Foundation for regime gate
6. **Structure Analyzer** - BOS displacement, trap detection
7. **Volatility Analyzer** - ATR expansion detection
8. **Momentum Analyzer** - Body %, follow-through

### Phase 3: Scoring & Sizing
9. **ExpansionScorer** - Combines all analysis
10. **LotSizer** - Dynamic sizing based on score
11. **Daily Loss Tracker** - Risk management

### Phase 4: Integration
12. **Update recommend_trade** - Integrate gates/scorer/sizer
13. **Update agent workflow** - Add pre-trade validation step
14. **Telemetry** - Track which gates reject trades

---

## Key Technical Challenges

### 1. **Day Type Classification**
- Need to analyze session candles (from 9:15)
- Detect inside day (high < prev high, low > prev low)
- Detect narrow range (range < X% of ATR)
- Detect trap resolution (fake break → reclaim → displacement)

**Solution**: Create `DayTypeClassifier` that analyzes session candles.

### 2. **ATR Expansion Detection**
- Calculate session ATR median (from 9:15 to current time)
- Calculate ATR slope (rate of change)
- Detect expansion (current ATR > median AND slope > 0)

**Solution**: Create `VolatilityAnalyzer` using existing ATR calculation.

### 3. **Expected Move Calculation**
- Use recent momentum (last N candles)
- Factor in volatility (ATR)
- Calculate expected index move in points
- Convert to premium: `index_move × delta`

**Solution**: Create `MomentumAnalyzer` with expected move calculation.

### 4. **Trap Detection**
- Detect fake breakout (price breaks structure, then reverses)
- Detect reclaim (price moves back above/below structure)
- Detect displacement (strong move in opposite direction)

**Solution**: Enhance `analyze_structure_15m` or create `StructureAnalyzer`.

### 5. **Strike Quality Validation**
- Extract delta from option chain contracts
- Calculate spread %: `(ask - bid) / mid_price × 100`
- Validate strike distance from ATM

**Solution**: Enhance `fetch_option_chain` to return delta/spread, or add validation in `PreTradeGate`.

---

## Integration Points

### 1. **Update `recommend_trade` Tool**

```ruby
# lib/vyapari/tools/recommend_trade.rb

def call(p)
  # Get all context
  trend = p["trend"]
  options = p["options"]
  candles_5m = p["candles_5m"] # Need 5m candles for analysis
  candles_15m = p["candles_15m"] # Need 15m candles for structure

  # Run pre-trade gate
  gate_result = Options::PreTradeGate.run(
    trend: trend,
    options: options,
    candles_5m: candles_5m,
    candles_15m: candles_15m,
    current_time: Time.now
  )

  unless gate_result[:allowed]
    return {
      action: "NO_TRADE",
      reason: gate_result[:reason],
      failed_gates: gate_result[:failed_gates]
    }
  end

  # Calculate expansion score
  score = Options::ExpansionScorer.score(
    trend: trend,
    structure: gate_result[:structure],
    volatility: gate_result[:volatility],
    momentum: gate_result[:momentum],
    time_window: gate_result[:time_window],
    strike_quality: gate_result[:strike_quality]
  )

  # Determine lot size
  lot_size = Options::LotSizer.size_for(
    score: score,
    daily_loss_cap_remaining: Trading::DailyLossTracker.remaining
  )

  # If score too low, block trade
  if lot_size == 0
    return {
      action: "NO_TRADE",
      reason: "Expansion score too low: #{score}/100",
      score: score
    }
  end

  # Proceed with trade recommendation
  # ... existing logic ...

  {
    action: "BUY",
    side: side,
    security_id: security_id,
    entry_price: premium,
    stop_loss_price: premium * 0.65,
    target_price: premium * 1.4,
    quantity: lot_size, # Use calculated lot size
    expansion_score: score,
    gate_result: gate_result
  }
end
```

### 2. **Update Agent Workflow**

Add new tool: `validate_trade_setup` (optional, or integrate into `recommend_trade`)

Or enhance `recommend_trade` to include all validation (recommended).

### 3. **Context Management**

Agent needs to store:
- `candles_5m` - For momentum/volatility analysis
- `candles_15m` - For structure analysis
- `option_chain` - For strike quality
- `trend` - For regime classification

---

## Testing Strategy

### Unit Tests Required

1. **PreTradeGate Tests**
   - Test each gate individually
   - Test gate combinations
   - Test edge cases (market open, lunch time, etc.)

2. **ExpansionScorer Tests**
   - Test scoring with various inputs
   - Test score boundaries (50, 65, 75, 85)
   - Test weight distribution

3. **LotSizer Tests**
   - Test lot sizing based on score
   - Test daily loss cap constraint
   - Test edge cases (score = 50, 65, 75, 85)

4. **DayTypeClassifier Tests**
   - Test trend day detection
   - Test trap resolution detection
   - Test range expansion detection
   - Test invalid day types

5. **StructureAnalyzer Tests**
   - Test BOS with displacement
   - Test trap failure retest
   - Test range break with follow-through

6. **VolatilityAnalyzer Tests**
   - Test ATR expansion detection
   - Test session ATR median calculation
   - Test ATR slope calculation

### Integration Tests

- End-to-end workflow with gates/scorer/sizer
- Test with real market data (NIFTY, BANKNIFTY)
- Test rejection scenarios (weak trades blocked)
- Test acceptance scenarios (strong trades allowed)

---

## Data Requirements

### From Existing Tools

1. **`analyze_structure_15m`** - Returns structure (bullish/bearish/range)
   - **Enhance**: Add BOS displacement detection, trap detection

2. **`analyze_trend`** - Returns trend, RSI, ADX, EMA, volume indicators
   - **Enhance**: Add day type classification

3. **`fetch_option_chain`** - Returns contracts with delta, premium, spread
   - **Enhance**: Calculate spread %, validate delta range

4. **`fetch_intraday_history`** - Returns candles (5m, 15m)
   - **Enhance**: Ensure session candles available (from 9:15)

### New Data Needed

1. **Session candles** - From 9:15 to current time (for day type classification)
2. **ATR values** - Historical ATR for session median calculation
3. **Delta values** - From option chain contracts
4. **Spread data** - Bid/ask from option chain
5. **Daily loss tracking** - Current day's P&L

---

## Next Steps

1. **Create Research Implementation Plan** - Detailed breakdown of each component
2. **Generate Ruby Code** - Implement PreTradeGate, ExpansionScorer, LotSizer
3. **Unit Tests** - Test each component in isolation
4. **Integration** - Wire into existing `recommend_trade` tool
5. **Telemetry** - Add logging to track gate rejections and scores

---

## Questions to Resolve

1. **Time Zone**: India Standard Time (IST) for time windows?
2. **Session Start**: 9:15 AM IST for day type classification?
3. **Delta Source**: Available in DhanHQ option chain response?
4. **Spread Calculation**: Bid/ask available in option chain?
5. **Daily Loss Cap**: What's the default cap? User-configurable?
6. **Expected Move**: Use ATR-based calculation or momentum-based?

---

## Conclusion

The existing codebase has **strong foundations**:
- ✅ Structure analysis (needs enhancement)
- ✅ Trend analysis (needs day type classification)
- ✅ Technical indicators (ATR available)
- ✅ Option chain fetching (needs strike quality validation)

**Key Gaps**:
- ❌ Day type classification
- ❌ ATR expansion detection
- ❌ Trap detection
- ❌ Expected move calculation
- ❌ Strike quality validation
- ❌ Lot sizing logic
- ❌ Daily loss tracking

**Estimated Implementation**: 3-4 weeks for full integration with testing.

**Recommended Approach**: Start with Phase 1 (core gates), then Phase 2 (enhanced analysis), then Phase 3 (scoring/sizing), then Phase 4 (integration).

