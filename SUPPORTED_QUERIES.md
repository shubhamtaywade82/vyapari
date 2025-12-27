# Supported Queries - Vyapari Trading System

This document lists all the queries currently supported by the Vyapari system. The system uses natural language processing to understand your queries and route them to the appropriate DhanHQ API tools.

## Quick Reference

### Most Common Queries

**Price Check:**
- `What is NIFTY's current price?`
- `Get RELIANCE LTP`

**Historical Data:**
- `Show me NIFTY 5 minute candles`
- `Get NIFTY daily candles`

**Options:**
- `What is NIFTY option chain`

**Account:**
- `My balance`
- `Show me my positions`
- `List orders`

### Usage

Run queries using the `exe/vyapari` command:
```bash
exe/vyapari "What is NIFTY's current price?"
exe/vyapari "Show me NIFTY 5 minute candles"
exe/vyapari "What is NIFTY option chain"
```

## Table of Contents

1. [Market Data Queries](#market-data-queries)
2. [Historical Data Queries](#historical-data-queries)
3. [Options Data Queries](#options-data-queries)
4. [Account & Portfolio Queries](#account--portfolio-queries)
5. [Order & Trade Queries](#order--trade-queries)
6. [Query Format Guidelines](#query-format-guidelines)

---

## Market Data Queries

Get real-time market data for indices, stocks, and derivatives.

### Last Traded Price (LTP)

Get the current/last traded price for any instrument.

**Examples:**
```
What is NIFTY's current price?
Get NIFTY LTP
Show me NIFTY index current ltp
What is NIFTY index price?
NIFTY LTP
Get RELIANCE LTP
```

**Supported Instruments:**
- Indices: NIFTY, BANKNIFTY, SENSEX, NIFTY50
- Stocks: Any NSE/BSE listed stock (e.g., RELIANCE, TCS, INFY)

**Output:**
- `ltp`: Last traded price
- `timestamp`: Timestamp of the price

---

### Market Quote

Get detailed market quote with bid/ask, volume, and other market data.

**Examples:**
```
Get NIFTY quote
Show me NIFTY market quote
Fetch NIFTY quote
```

**Output:**
- `bid`: Best bid price
- `ask`: Best ask price
- `ltp`: Last traded price
- `volume`: Trading volume
- `open_interest`: Open interest (for F&O instruments)

---

### OHLC Data

Get Open, High, Low, Close data for the current trading day.

**Examples:**
```
Get NIFTY OHLC
Show me NIFTY OHLC data
Fetch NIFTY open high low close
```

**Output:**
- `open`: Opening price
- `high`: Highest price
- `low`: Lowest price
- `close`: Closing price (or current price if market is open)

---

## Historical Data Queries

Get historical price data (candles) for technical analysis.

### Intraday Candles

Get intraday candles for any timeframe (1m, 5m, 15m, 1h, etc.).

**Examples:**
```
Show me NIFTY 5 minute candles
Get NIFTY intraday 15min
NIFTY 1 minute candles
Show me NIFTY 5min data
Get NIFTY 1h candles
```

**Supported Timeframes:**
- `1` - 1 minute
- `5` - 5 minutes
- `15` - 15 minutes
- `25` - 25 minutes
- `60` - 1 hour

**Date Handling:**
- Automatically uses current trading dates
- `to_date`: Today (or last trading day if weekend)
- `from_date`: Last trading day before `to_date` (ensures previous session context)
- Never uses old dates - always current year

**Output:**
- `candles`: Array of OHLC candles
- `interval`: Timeframe used
- `complete`: Whether last candle is closed

**Dependencies:**
- Requires `dhan.instrument.find` to be called first
- Requires `analysis_context.interval`, `analysis_context.from_date`, `analysis_context.to_date`

---

### Daily Candles

Get daily candles for swing trading and longer-term analysis.

**Examples:**
```
Show me NIFTY daily candles
Get NIFTY daily data
NIFTY daily candles
Show me NIFTY daily
```

**Date Handling:**
- Automatically uses current trading dates
- `to_date`: Today (or last trading day if weekend)
- `from_date`: 30 days ago (or configurable range)
- Never uses old dates - always current year

**Output:**
- `candles`: Array of daily OHLC candles
- `interval`: "1D" (daily)

**Dependencies:**
- Requires `dhan.instrument.find` to be called first
- Requires `analysis_context.from_date`, `analysis_context.to_date`

---

## Options Data Queries

Get options-specific data including expiry lists and option chains.

### Expiry List

Get available expiry dates for an underlying instrument.

**Examples:**
```
Get NIFTY expiries
Show me NIFTY expiry list
NIFTY expiries
```

**Output:**
- `expiry_list`: Array of expiry dates (YYYY-MM-DD format)

**Dependencies:**
- Requires `dhan.instrument.find` to be called first
- Requires `instrument.security_id` and `instrument.exchange_segment`

**Note:** This tool is automatically called before `dhan.option.chain` if expiry is not provided.

---

### Option Chain

Get complete option chain with strikes, premiums, Greeks, and open interest.

**Examples:**
```
What is NIFTY option chain
Get NIFTY option chain
Show me NIFTY option chain
NIFTY option chain
```

**Dependencies:**
- **REQUIRES** `dhan.instrument.find` to be called first
- **REQUIRES** `dhan.option.expiries` to be called first (to get expiry_list)
- Automatically uses `expiry_list[0]` (nearest expiry) if not specified

**Output:**
- `contracts`: Array of option contracts with:
  - Strike prices
  - Call and Put premiums
  - Greeks (Delta, Gamma, Theta, Vega)
  - Open interest
  - Volume
- `spot_price`: Current spot price of underlying

**Important:** The system will automatically:
1. Call `dhan.instrument.find` to resolve symbol
2. Call `dhan.option.expiries` to get available expiries
3. Use the nearest expiry (`expiry_list[0]`) for the option chain
4. Call `dhan.option.chain` with all required parameters

---

## Account & Portfolio Queries

Get account and portfolio information.

### Account Balance

Get available funds, margin, and account balance.

**Examples:**
```
What is my balance?
Show me my funds
Get my account balance
My balance
Account funds
Margin
```

**Output:**
- `available`: Available balance
- `utilized`: Utilized margin
- `total`: Total balance

---

### Positions

Get all open positions.

**Examples:**
```
Show me my positions
List my positions
Get positions
My positions
Current positions
```

**Output:**
- `positions`: Array of open positions with:
  - Symbol
  - Quantity
  - Average price
  - Current price
  - P&L

---

### Holdings

Get all holdings (stocks/ETFs in demat account).

**Examples:**
```
Show me my holdings
List holdings
Get holdings
My holdings
```

**Output:**
- `holdings`: Array of holdings with:
  - Symbol
  - Quantity
  - Average price
  - Current price

---

### Orders

Get all orders (pending, filled, cancelled).

**Examples:**
```
Show me my orders
List orders
Get orders
My orders
Current orders
```

**Output:**
- `orders`: Array of orders with:
  - Order ID
  - Symbol
  - Quantity
  - Order type
  - Status
  - Price

---

### Today's Trades

Get all trades executed today.

**Examples:**
```
Show me today's trades
Get today's trades
List trades
My trades today
```

**Output:**
- `trades`: Array of trades with:
  - Trade ID
  - Symbol
  - Quantity
  - Price
  - Timestamp

---

## Order & Trade Queries

**Note:** Order placement and modification queries are not yet fully supported through the natural language interface. These operations require explicit validation and risk checks. Use the dedicated trading workflows for order execution.

---

## Query Format Guidelines

### General Guidelines

1. **Natural Language**: The system understands natural language queries. You don't need to use specific syntax.

2. **Symbol Recognition**:
   - Indices: NIFTY, BANKNIFTY, SENSEX (automatically detected as `IDX_I`)
   - Stocks: Any valid stock symbol (automatically detected as `NSE_EQ` or `BSE_EQ`)

3. **Date Handling**:
   - Historical queries automatically use current trading dates
   - Never uses old dates (e.g., 2022, 2023)
   - Handles weekends and market holidays automatically

4. **Timeframe Recognition**:
   - Intraday: "1m", "5min", "15min", "1h", "60min"
   - Daily: "daily", "1D", "day"

5. **Dependencies**:
   - The system automatically calls prerequisite tools
   - For example, `dhan.option.chain` automatically calls `dhan.instrument.find` and `dhan.option.expiries` first

### Common Query Patterns

**Price Queries:**
- "What is [SYMBOL] price?"
- "[SYMBOL] LTP"
- "Get [SYMBOL] current price"

**Historical Data:**
- "Show me [SYMBOL] [TIMEFRAME] candles"
- "Get [SYMBOL] intraday [TIMEFRAME]"
- "[SYMBOL] daily candles"

**Options:**
- "[SYMBOL] option chain"
- "Get [SYMBOL] option chain"

**Account:**
- "My balance"
- "Show positions"
- "List orders"

---

## Error Handling

If a query fails, the system will return an error message explaining:
- What went wrong
- What dependencies are missing
- How to fix the query

**Common Errors:**
- `Dependency validation failed`: Required prerequisite tools not called
- `Missing required output`: Previous tool didn't produce expected output
- `Invalid state`: Tool called in wrong system state
- `Tool forbidden`: Tool not allowed in current context

---

## Examples by Use Case

### Quick Price Check
```
What is NIFTY's current price?
Get RELIANCE LTP
```

### Technical Analysis Setup
```
Show me NIFTY 5 minute candles
Get NIFTY daily candles
```

### Options Trading Research
```
What is NIFTY option chain
Get BANKNIFTY option chain
```

### Portfolio Monitoring
```
My balance
Show me my positions
List orders
```

### Multi-Step Analysis
The system automatically handles multi-step queries:
- "NIFTY option chain" → automatically calls instrument.find → expiries → option.chain
- "NIFTY 5min candles" → automatically calls instrument.find → history.intraday

---

## Technical Details

### Tool Dependencies

The system enforces explicit dependencies:

1. **Data Dependencies**: Tool B requires output from Tool A
   - Example: `dhan.option.chain` requires `expiry_list` from `dhan.option.expiries`

2. **State Dependencies**: Tool only allowed in specific states
   - Example: Trading tools only in `ORDER_EXECUTION` state

3. **Safety Dependencies**: Tool requires guards to pass
   - Example: RiskGuard must pass before order placement

4. **Temporal Dependencies**: Tool call limits and ordering
   - Example: `max_calls_per_trade: 1` for order placement

### Derived Inputs

Some tool inputs are automatically derived from previous tool outputs:
- `expiry` → from `expiry_list[0]`
- `security_id` → from `instrument.security_id`
- `exchange_segment` → from `instrument.exchange_segment`

### Context Management

The system maintains execution context with:
- `tool_calls`: Tracks which tools have been called
- `instrument`: Instrument data from `dhan.instrument.find`
- `expiry_list`: Expiry dates from `dhan.option.expiries`
- `intraday_candles`: Historical candles
- `daily_candles`: Daily candles
- And more...

---

## Future Enhancements

Planned additions:
- Order placement through natural language
- Position modification queries
- Advanced technical analysis queries
- Strategy backtesting queries
- Alert and notification queries

---

## Support

For issues or questions:
1. Check error messages for dependency requirements
2. Verify symbol names are correct
3. Ensure dates are current (system handles this automatically)
4. Check that required tools are called in sequence

---

**Last Updated:** 2025-12-27
**Version:** 1.0.0

