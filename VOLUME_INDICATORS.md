# Volume Indicators Guide

This guide explains how to use volume-based technical indicators in Vyapari using both:
- `technical-analysis` (intrinio) - Comprehensive indicator library
- `ruby-technical-analysis` (johnnypaper) - Additional unique indicators

## Overview

Volume indicators help confirm price movements and identify potential reversals. They measure the strength of price movements by analyzing trading volume.

## Available Volume Indicators

### 1. **On-Balance Volume (OBV)**
- **Purpose**: Cumulative volume indicator that adds volume on up days and subtracts on down days
- **Interpretation**:
  - Rising OBV = Buying pressure (bullish)
  - Falling OBV = Selling pressure (bearish)
  - OBV divergence from price = Potential reversal signal

**Usage:**
```ruby
require_relative "lib/vyapari/indicators/technical_analysis_adapter"

candles = [...] # Your candle data
adapter = Vyapari::Indicators::TechnicalAnalysisAdapter.new(candles)
obv_value = adapter.latest_obv
```

### 2. **Chaikin Money Flow (CMF)**
- **Purpose**: Volume-weighted average of accumulation/distribution
- **Range**: -1 to +1
- **Interpretation**:
  - CMF > 0 = Buying pressure (bullish)
  - CMF < 0 = Selling pressure (bearish)
  - CMF > 0.25 = Strong buying pressure
  - CMF < -0.25 = Strong selling pressure

**Usage:**
```ruby
adapter = Vyapari::Indicators::TechnicalAnalysisAdapter.new(candles)
cmf_value = adapter.latest_cmf(period: 20)
```

### 3. **Money Flow Index (MFI)**
- **Purpose**: Volume-weighted RSI (combines price and volume)
- **Range**: 0-100
- **Interpretation**:
  - MFI > 80 = Overbought (potential sell signal)
  - MFI < 20 = Oversold (potential buy signal)
  - MFI > 50 = Buying pressure
  - MFI < 50 = Selling pressure

**Usage:**
```ruby
adapter = Vyapari::Indicators::TechnicalAnalysisAdapter.new(candles)
mfi_value = adapter.latest_mfi(period: 14)
```

### 4. **Volume Rate of Change (VROC)**
- **Purpose**: Momentum of volume changes
- **Interpretation**:
  - Positive VROC = Increasing volume (confirms trend)
  - Negative VROC = Decreasing volume (weakens trend)

**Usage:**
```ruby
adapter = Vyapari::Indicators::TechnicalAnalysisAdapter.new(candles)
vroc_values = adapter.vroc(period: 12)
latest_vroc = vroc_values.last&.vroc
```

### 5. **Accumulation/Distribution Line (A/D)**
- **Purpose**: Cumulative volume indicator based on price location
- **Interpretation**:
  - Rising A/D = Accumulation (buying)
  - Falling A/D = Distribution (selling)

**Usage:**
```ruby
adapter = Vyapari::Indicators::TechnicalAnalysisAdapter.new(candles)
ad_values = adapter.accumulation_distribution
latest_ad = ad_values.last&.ad
```

## Quick Usage with Helper Module

Use the `VolumeIndicators` helper module for easy access:

```ruby
require_relative "lib/vyapari/indicators/volume_indicators"

candles = [...] # Your candle data

# Get all volume indicators at once
indicators = Vyapari::Indicators::VolumeIndicators.calculate_all(candles)
# => { obv: 12345.0, cmf: 0.15, mfi: 65.5, vroc: 12.3, accumulation_distribution: 5678.0 }

# Get individual indicators
mfi = Vyapari::Indicators::VolumeIndicators.mfi(candles, period: 14)
cmf = Vyapari::Indicators::VolumeIndicators.cmf(candles, period: 20)
obv = Vyapari::Indicators::VolumeIndicators.obv(candles)

# Get overall volume trend
volume_trend = Vyapari::Indicators::VolumeIndicators.volume_trend(candles)
# => "bullish", "bearish", or "neutral"
```

## Integration with analyze_trend

You can enhance the `analyze_trend` tool to include volume confirmation:

```ruby
# In analyze_trend.rb
require_relative "../indicators/volume_indicators"

def call(p)
  candles_data = p["candles"]
  # ... existing code ...

  # Calculate volume indicators
  volume_indicators = Indicators::VolumeIndicators.calculate_all(candles_data)
  volume_trend = Indicators::VolumeIndicators.volume_trend(candles_data)

  # Use volume to confirm price trend
  trend_confirmed = if trend == "bullish" && volume_trend == "bullish"
    true  # Price and volume both bullish
  elsif trend == "bearish" && volume_trend == "bearish"
    true  # Price and volume both bearish
  else
    false # Divergence - weaker signal
  end

  {
    trend: trend,
    rsi: rsi,
    adx: adx,
    ema_fast: ema_fast,
    ema_slow: ema_slow,
    volume_trend: volume_trend,
    mfi: volume_indicators[:mfi],
    cmf: volume_indicators[:cmf],
    obv: volume_indicators[:obv],
    trend_confirmed: trend_confirmed,
    recommendation: build_recommendation(trend, volume_trend, trend_confirmed)
  }
end
```

## Trading Signals with Volume

### Bullish Signal (Buy)
- Price trend: Bullish (EMA Fast > Slow, ADX > 25)
- Volume confirmation: MFI > 50, CMF > 0, OBV rising
- **Action**: Strong buy signal

### Bearish Signal (Sell/Short)
- Price trend: Bearish (EMA Fast < Slow, ADX > 25)
- Volume confirmation: MFI < 50, CMF < 0, OBV falling
- **Action**: Strong sell/short signal

### Weak Signal (Avoid)
- Price trend: Bullish/Bearish
- Volume divergence: MFI and CMF contradict price trend
- **Action**: Avoid trading - weak confirmation

## Example: Complete Analysis

```ruby
require_relative "lib/vyapari/indicators/technical_analysis_adapter"
require_relative "lib/vyapari/indicators/volume_indicators"

# Your candles from fetch_intraday_history
candles = [
  { "open" => 100, "high" => 105, "low" => 99, "close" => 104, "volume" => 1000000 },
  { "open" => 104, "high" => 106, "low" => 103, "close" => 105, "volume" => 1200000 },
  # ... more candles
]

# Price-based analysis (existing)
closes = candles.map { |c| c["close"] }
rsi = Vyapari::Indicators::RSI.calculate(closes)
adx = Vyapari::Indicators::ADX.calculate(candles)
ema_fast = Vyapari::Indicators::EMA.calculate(closes, 9)
ema_slow = Vyapari::Indicators::EMA.calculate(closes, 21)

# Volume-based analysis (new)
volume_trend = Vyapari::Indicators::VolumeIndicators.volume_trend(candles)
volume_indicators = Vyapari::Indicators::VolumeIndicators.calculate_all(candles)

# Combined analysis
if adx > 25 && ema_fast > ema_slow && volume_trend == "bullish"
  puts "Strong bullish signal with volume confirmation"
elsif adx > 25 && ema_fast < ema_slow && volume_trend == "bearish"
  puts "Strong bearish signal with volume confirmation"
else
  puts "Weak signal - avoid trading"
end
```

## Available Indicators by Library

### intrinio/technical-analysis (Primary)
- OBV, CMF, MFI, VROC, A/D, VPT, VWAP
- NVI, Force Index, Ease of Movement
- RSI, MACD, Bollinger Bands, Stochastic
- ADX, ATR, CCI, Williams %R
- And many more...

### ruby-technical-analysis (Unique Indicators)
- **Intraday Momentum Index (IMI)** - Unique to this library
- **Chande Momentum Oscillator** - Unique to this library
- **Volume Oscillator** - Unique to this library
- **Pivot Points** - Unique to this library
- Bollinger Bands, RSI, Stochastic (also in intrinio)

## Installation

Both gems are already added to `vyapari.gemspec`. Install them with:

```bash
bundle install
```

## References

- [intrinio/technical-analysis GitHub](https://github.com/intrinio/technical-analysis)
- [ruby-technical-analysis Documentation](https://rubytechnicalanalysis.com/)
- [ruby-technical-analysis GitHub](https://github.com/johnnypaper/ruby-technical-analysis)

