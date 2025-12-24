# Indicator Values Summary

This document explains the technical indicators used in Vyapari for market trend analysis.

## Overview

The `analyze_trend` tool uses three key indicators to determine market direction:
1. **RSI (Relative Strength Index)** - Momentum oscillator
2. **ADX (Average Directional Index)** - Trend strength indicator
3. **EMA (Exponential Moving Average)** - Trend direction indicator

## RSI (Relative Strength Index)

**Purpose**: Measures the speed and magnitude of price changes (momentum)

**Range**: 0 to 100

**Interpretation**:
- **RSI > 70**: Overbought condition (potential sell signal)
- **RSI < 30**: Oversold condition (potential buy signal)
- **RSI 30-70**: Neutral zone

**Default Period**: 14 days

**Usage in Vyapari**:
- Calculated from closing prices
- Returned in trend analysis for reference
- Not directly used in trend determination (ADX + EMA are primary)

## ADX (Average Directional Index)

**Purpose**: Measures the strength of a trend (not direction)

**Range**: 0 to 100

**Interpretation**:
- **ADX < 20**: Weak/no trend (choppy market)
- **ADX 20-25**: Developing trend
- **ADX > 25**: Strong trend
- **ADX > 50**: Very strong trend (rare)

**Default Period**: 14 days

**Usage in Vyapari**:
- **Primary filter**: ADX > 25 required for bullish/bearish signals
- If ADX ≤ 25 → Market is "avoid" (choppy, no clear trend)
- Calculated from high, low, and close prices (requires full candle data)

## EMA (Exponential Moving Average)

**Purpose**: Smooths price data to identify trend direction

**Two EMAs Used**:
- **EMA Fast**: 9-period (short-term trend)
- **EMA Slow**: 21-period (long-term trend)

**Interpretation**:
- **EMA Fast > EMA Slow**: Uptrend (bullish)
- **EMA Fast < EMA Slow**: Downtrend (bearish)
- **EMA Fast ≈ EMA Slow**: Sideways/choppy market

**Usage in Vyapari**:
- Combined with ADX to determine trend direction
- Calculated from closing prices

## Trend Determination Logic

The `analyze_trend` tool uses the following logic:

```ruby
if ADX > 25 && EMA_Fast > EMA_Slow
  trend = "bullish"  # Strong uptrend
elsif ADX > 25 && EMA_Fast < EMA_Slow
  trend = "bearish"  # Strong downtrend
else
  trend = "avoid"    # Weak trend or choppy market
end
```

### Decision Matrix

| ADX  | EMA Fast vs Slow | Trend Result       |
| ---- | ---------------- | ------------------ |
| > 25 | Fast > Slow      | **Bullish**        |
| > 25 | Fast < Slow      | **Bearish**        |
| ≤ 25 | Any              | **Avoid** (choppy) |

## Return Values

The `analyze_trend` tool returns:

```ruby
{
  trend: "bullish" | "bearish" | "avoid",
  rsi: <0-100>,           # RSI value
  adx: <0-100>,           # ADX value
  ema_fast: <price>,      # 9-period EMA
  ema_slow: <price>,      # 21-period EMA
  recommendation: "Market trend is BULLISH" | "Avoid trading - market is choppy"
}
```

## Example Scenarios

### Scenario 1: Strong Bullish Trend
- ADX: 32 (strong trend)
- EMA Fast: 19,500
- EMA Slow: 19,200
- RSI: 65
- **Result**: `trend: "bullish"` → Proceed with option buying (CE calls)

### Scenario 2: Strong Bearish Trend
- ADX: 28 (strong trend)
- EMA Fast: 19,200
- EMA Slow: 19,500
- RSI: 35
- **Result**: `trend: "bearish"` → Proceed with option buying (PE puts)

### Scenario 3: Choppy Market
- ADX: 18 (weak trend)
- EMA Fast: 19,350
- EMA Slow: 19,340
- RSI: 50
- **Result**: `trend: "avoid"` → NO_TRADE recommended

## Notes

- **RSI** is informational and not used in trend determination
- **ADX** is the primary filter - must be > 25 for any trade signal
- **EMA crossover** determines direction when ADX is strong
- All indicators use default periods optimized for intraday trading
- Indicators are calculated from historical candle data (typically last 7 days)

