# Technical Indicators Comparison

This document shows which indicators are available from each library and which library is used for each indicator in Vyapari.

## Library Selection Strategy

- **intrinio/technical-analysis**: Primary library for most indicators (comprehensive coverage)
- **ruby-technical-analysis**: Used only for unique indicators not available in intrinio

## Indicator Availability

### Volume Indicators

| Indicator                        | intrinio | ruby-ta | Used Library |
| -------------------------------- | -------- | ------- | ------------ |
| OBV (On-Balance Volume)          | ✅        | ❌       | intrinio     |
| CMF (Chaikin Money Flow)         | ✅        | ✅       | intrinio     |
| MFI (Money Flow Index)           | ✅        | ❌       | intrinio     |
| VROC (Volume Rate of Change)     | ✅        | ❌       | intrinio     |
| A/D (Accumulation/Distribution)  | ✅        | ❌       | intrinio     |
| VPT (Volume-price Trend)         | ✅        | ❌       | intrinio     |
| VWAP (Volume Weighted Avg Price) | ✅        | ❌       | intrinio     |
| NVI (Negative Volume Index)      | ✅        | ❌       | intrinio     |
| Force Index                      | ✅        | ❌       | intrinio     |
| Ease of Movement                 | ✅        | ❌       | intrinio     |
| Volume Oscillator                | ❌        | ✅       | ruby-ta      |

### Price Indicators

| Indicator                       | intrinio | ruby-ta | Used Library |
| ------------------------------- | -------- | ------- | ------------ |
| RSI (Relative Strength Index)   | ✅        | ✅       | intrinio     |
| MACD                            | ✅        | ✅       | intrinio     |
| Bollinger Bands                 | ✅        | ✅       | intrinio     |
| Stochastic Oscillator           | ✅        | ✅       | intrinio     |
| ADX (Average Directional Index) | ✅        | ❌       | intrinio     |
| ATR (Average True Range)        | ✅        | ❌       | intrinio     |
| CCI (Commodity Channel Index)   | ✅        | ❌       | intrinio     |
| Williams %R                     | ✅        | ✅       | intrinio     |
| Intraday Momentum Index (IMI)   | ❌        | ✅       | ruby-ta      |
| Chande Momentum Oscillator      | ❌        | ✅       | ruby-ta      |
| Pivot Points                    | ❌        | ✅       | ruby-ta      |

### Moving Averages

| Indicator                        | intrinio | ruby-ta | Used Library |
| -------------------------------- | -------- | ------- | ------------ |
| SMA (Simple Moving Average)      | ✅        | ❌       | intrinio     |
| EMA (Exponential Moving Average) | ✅        | ✅       | intrinio     |
| WMA (Weighted Moving Average)    | ✅        | ❌       | intrinio     |
| TRIX (Triple Exponential)        | ✅        | ❌       | intrinio     |

### Other Indicators (intrinio only)

- Awesome Oscillator (AO)
- Donchian Channel (DC)
- Ichimoku Kinko Hyo (ICHIMOKU)
- Keltner Channel (KC)
- Know Sure Thing (KST)
- Mass Index (MI)
- True Strength Index (TSI)
- Ultimate Oscillator (UO)
- Vortex Indicator (VI)

## Usage in Vyapari

All indicators are accessible through the unified `TechnicalAnalysisAdapter`:

```ruby
require_relative "lib/vyapari/indicators/technical_analysis_adapter"

candles = [...] # Your candle data
adapter = Vyapari::Indicators::TechnicalAnalysisAdapter.new(candles)

# Volume indicators (from intrinio)
obv = adapter.latest_obv
cmf = adapter.latest_cmf(period: 20)
mfi = adapter.latest_mfi(period: 14)
vwap = adapter.latest_vwap

# Unique indicators (from ruby-ta)
imi = adapter.intraday_momentum_index(period: 14)
cmo = adapter.chande_momentum_oscillator(period: 9)
volume_osc = adapter.volume_oscillator(fast_period: 5, slow_period: 10)
pivots = adapter.pivot_points

# Price indicators (from intrinio)
rsi = adapter.latest_rsi(period: 14)
macd = adapter.macd
bb = adapter.bollinger_bands(period: 20)
atr = adapter.latest_atr(period: 14)
```

## Why Both Libraries?

1. **intrinio/technical-analysis**:
   - More comprehensive (40+ indicators)
   - Better maintained and documented
   - Standard format (Array of Hashes)
   - Used for 95% of indicators

2. **ruby-technical-analysis**:
   - Unique indicators (IMI, Chande Momentum, Volume Oscillator, Pivot Points)
   - Well-tested with examples from "Technical Analysis from A to Z"
   - Used only when indicator is not available in intrinio

## Migration Notes

If you're currently using custom indicator implementations:
- Keep using them if they work well
- Consider migrating to library implementations for consistency
- Volume indicators now require volume data in candles (already available)

