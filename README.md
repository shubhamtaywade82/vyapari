# Vyapari

**Vyapari** is an AI-powered options trading agent built in Ruby that uses Large Language Models (LLMs) via Ollama to analyze market trends and recommend option trading strategies. It integrates with the DhanHQ API to fetch real-time market data, calculate technical indicators, and generate trade recommendations.

## Features

- 🤖 **AI-Powered Agent**: Uses Ollama LLM to orchestrate trading analysis workflow
- 📊 **Technical Analysis**: Calculates RSI, ADX, and EMA indicators for trend analysis
- 📈 **Options Trading**: Fetches option chains and recommends trades based on market trends
- 🔄 **Context-Aware**: Maintains persistent context across tool calls to prevent state loss
- 🛡️ **Robust Error Handling**: Validates prerequisites, injects arguments from context, and prevents invalid tool calls
- 📝 **Comprehensive Logging**: Detailed logs for debugging and monitoring agent execution

## Architecture

Vyapari follows a multi-layered architecture:

1. **Agent Layer** (`Vyapari::Agent`): Orchestrates the LLM interaction and tool execution
   - Manages message history and context
   - Enforces tool prerequisites
   - Injects arguments from context
   - Prevents LLM hallucination and code generation

2. **Tool Layer** (`Vyapari::Tools`): Modular tools for trading operations
   - `FindInstrument`: Locates trading instruments
   - `FetchIntradayHistory`: Retrieves historical price data
   - `AnalyzeTrend`: Calculates technical indicators and determines market trend
   - `FetchExpiryList`: Gets available option expiry dates
   - `FetchOptionChain`: Retrieves option chain data
   - `RecommendTrade`: Generates trade recommendations

3. **Indicator Layer** (`Vyapari::Indicators`): Technical analysis calculations
   - RSI (Relative Strength Index)
   - ADX (Average Directional Index)
   - EMA (Exponential Moving Average)

4. **Trading Layer** (`Vyapari::Trading`): Risk management utilities
   - Position sizing calculations

## Installation

### Prerequisites

- Ruby >= 3.2.0
- Ollama installed and running (default: `http://localhost:11434`)
- DhanHQ API credentials

### Setup

1. Clone the repository:
```bash
git clone https://github.com/shubhamtaywade/vyapari.git
cd vyapari
```

2. Install dependencies:
```bash
bundle install
```

3. Set up environment variables (create `.env` file):
```bash
# Ollama Configuration
OLLAMA_URL=http://localhost:11434  # Optional, defaults to localhost:11434

# DhanHQ API Configuration
DHAN_CLIENT_ID=your_client_id
DHAN_ACCESS_TOKEN=your_access_token
DHAN_LOG_LEVEL=INFO  # Optional, defaults to INFO
```

4. Run the setup script:
```bash
bin/setup
```

## Usage

### Command Line

The simplest way to use Vyapari is via the command-line executable:

```bash
exe/vyapari "Analyze NIFTY index and recommend options trading strategy"
```

### Programmatic Usage

```ruby
require "vyapari"

# Configure DhanHQ (if not already configured)
Vyapari::Config.configure_dhan!

# Create and run the agent
agent = Vyapari::Agent.new
result = agent.run("NIFTY options buying")

puts result
```

## Workflow

The agent follows a strict sequential workflow with guaranteed state persistence:

1. **Find Instrument** → Locates the trading instrument (NIFTY, BANKNIFTY, stocks, etc.)
   - Stores: `instrument` in context
   - LLM provides: `exchange_segment`, `symbol`
   - Ruby uses: LLM arguments (first tool, no context yet)

2. **Fetch Intraday History** → Retrieves 7 days of 5-minute candle data
   - Stores: `candles` in context
   - LLM provides: `{}` (empty - parameters auto-injected)
   - Ruby injects: `security_id`, `exchange_segment`, `instrument`, `interval` from context

3. **Analyze Trend** → Calculates RSI, ADX, EMA and determines trend (bullish/bearish/avoid)
   - Stores: `trend` in context
   - LLM provides: `{}` (empty - parameters auto-injected)
   - Ruby injects: `candles` from context

4. **Fetch Expiry List** → Gets available option expiry dates
   - Stores: `expiry` in context (first valid expiry, handles expiry_passed logic)
   - LLM provides: `{}` (empty - parameters auto-injected)
   - Ruby injects: `underlying_seg`, `underlying_scrip`, `symbol` from context

5. **Fetch Option Chain** → Retrieves option chain data (only if trend is bullish/bearish)
   - Stores: `option_chain` in context
   - LLM provides: `{}` (empty - parameters auto-injected)
   - Ruby injects: `underlying_seg`, `underlying_scrip`, `symbol`, `expiry`, `trend` from context
   - Validates: Rejects if `trend` is "avoid"

6. **Recommend Trade** → Generates trade recommendation with entry, stop-loss, target, and quantity
   - LLM provides: `{}` (empty - parameters auto-injected)
   - Ruby injects: `trend`, `options` from context

### Context Management

The agent maintains persistent `@context` hash that stores results after each tool call:

```ruby
@context = {
  instrument: nil,    # From find_instrument
  candles: nil,        # From fetch_intraday_history
  trend: nil,          # From analyze_trend
  expiry: nil,         # From fetch_expiry_list
  option_chain: nil    # From fetch_option_chain
}
```

**Key Guarantees:**
- ✅ No empty parameters - all arguments auto-injected from context
- ✅ No invented values - Ruby controls all parameters
- ✅ No "avoid" trends passed to fetch_option_chain - validated and rejected
- ✅ No crashes - prerequisite guards prevent invalid calls
- ✅ State persistence - context updated after every tool call

## Tools

### FindInstrument

Finds trading instruments by symbol and exchange segment.

**Parameters** (LLM provides - first tool, no context yet):
- `exchange_segment`: Exchange segment (IDX_I for indices, NSE_EQ/BSE_EQ for stocks)
- `symbol`: Instrument symbol (e.g., "NIFTY", "BANKNIFTY")

**Returns**: `security_id`, `exchange_segment`, `instrument`, `instrument_type`, `symbol` (original symbol stored for later use)

**Stored in context**: `@context[:instrument]`

### FetchIntradayHistory

Fetches 7 days of intraday historical data.

**Parameters** (auto-injected from context - LLM calls with `{}`):
- `security_id`: Security ID from `@context[:instrument]`
- `exchange_segment`: Exchange segment from `@context[:instrument]`
- `instrument`: Instrument field from `@context[:instrument]`
- `interval`: Fixed to "5" (5-minute candles)

**Returns**: Hash with `candles` array containing candle objects with `open`, `high`, `low`, `close`, `volume`, `timestamp`

**Stored in context**: `@context[:candles]` (extracted from result)

### AnalyzeTrend

Analyzes market trend using technical indicators.

**Parameters** (auto-injected from context - LLM calls with `{}`):
- `candles`: Array of candle data from `@context[:candles]`

**Returns**:
- `trend`: "bullish", "bearish", or "avoid"
- `rsi`: Relative Strength Index value
- `adx`: Average Directional Index value
- `ema_fast`: Fast EMA (9 period)
- `ema_slow`: Slow EMA (21 period)
- `recommendation`: Human-readable recommendation

**Trend Logic**:
- **Bullish**: ADX > 25 AND EMA(9) > EMA(21)
- **Bearish**: ADX > 25 AND EMA(9) < EMA(21)
- **Avoid**: ADX ≤ 25 (choppy market, no clear trend)

**Stored in context**: `@context[:trend]` (extracted from result)

### FetchExpiryList

Fetches available option expiry dates.

**Parameters** (auto-injected from context - LLM calls with `{}`):
- `underlying_seg`: Exchange segment from `@context[:instrument]` (default: "IDX_I")
- `underlying_scrip`: Security ID as integer from `@context[:instrument]`
- `symbol`: Original symbol from `@context[:instrument]` (for fallback)

**Returns**: Array of expiry date strings (e.g., ["2025-12-30", "2026-01-06", ...])

**Stored in context**: `@context[:expiry]` (first valid expiry, handles expiry_passed logic - uses second expiry if first has passed after 4 PM)

### FetchOptionChain

Fetches option chain data for a specific expiry.

**Parameters** (auto-injected from context - LLM calls with `{}`):
- `underlying_seg`: Exchange segment from `@context[:instrument]`
- `underlying_scrip`: Security ID from `@context[:instrument]`
- `symbol`: Original symbol from `@context[:instrument]` (for fallback)
- `expiry`: Expiry date from `@context[:expiry]`
- `trend`: Market trend from `@context[:trend]` (must be "bullish" or "bearish")

**Validation**: Rejects if `trend` is "avoid" - raises `ArgumentError` directing to `recommend_trade` instead

**Returns**:
- `spot_price`: Current spot price
- `atm_strike`: At-the-money strike price
- `otm_strike`: Out-of-the-money strike price
- `side`: "CE" (Call) for bullish, "PE" (Put) for bearish
- `contracts`: Array of selected option contracts

**Stored in context**: `@context[:option_chain]`

### RecommendTrade

Generates trade recommendation based on analysis.

**Parameters** (auto-injected from context - LLM calls with `{}`):
- `options`: Option chain data from `@context[:option_chain]`
- `trend`: Market trend from `@context[:trend]`

**Returns**:
- `action`: "BUY" or "NO_TRADE" (if trend is "avoid" or "choppy")
- `side`: "CE" or "PE"
- `security_id`: Contract security ID
- `entry_price`: Recommended entry price
- `stop_loss_price`: Stop loss price (65% of entry)
- `target_price`: Target price (140% of entry)
- `quantity`: Position size (calculated based on premium, capped at 50 lots)

## Technical Indicators

Vyapari uses three key technical indicators for trend analysis:

### RSI (Relative Strength Index)
- **Range**: 0-100
- **Purpose**: Measures momentum
- **Interpretation**: >70 overbought, <30 oversold

### ADX (Average Directional Index)
- **Range**: 0-100
- **Purpose**: Measures trend strength
- **Interpretation**: >25 strong trend, ≤25 choppy market

### EMA (Exponential Moving Average)
- **Periods**: 9 (fast) and 21 (slow)
- **Purpose**: Identifies trend direction
- **Interpretation**: Fast > Slow = bullish, Fast < Slow = bearish

See [INDICATORS.md](INDICATORS.md) for detailed documentation.

## Configuration

### Ollama Configuration

Set the Ollama URL via environment variable:
```bash
export OLLAMA_URL=http://localhost:11434
```

Or pass a custom client to the agent:
```ruby
client = Vyapari::Client.new(url: "http://custom-ollama:11434")
agent = Vyapari::Agent.new(client: client)
```

### DhanHQ Configuration

DhanHQ is configured via environment variables:
- `DHAN_CLIENT_ID`: Your DhanHQ client ID
- `DHAN_ACCESS_TOKEN`: Your DhanHQ access token
- `DHAN_LOG_LEVEL`: Logging level (default: INFO)

Configure programmatically:
```ruby
Vyapari::Config.configure_dhan!
```

## Development

### Setup

```bash
# Install dependencies
bundle install

# Run setup script
bin/setup
```

### Running Tests

```bash
# Run RSpec tests
bundle exec rspec

# Run with coverage
COVERAGE=true bundle exec rspec
```

### Code Quality

```bash
# Run RuboCop
bundle exec rubocop

# Auto-fix issues
bundle exec rubocop -a
```

### Interactive Console

```bash
bin/console
```

### Building the Gem

```bash
# Build the gem
bundle exec rake build

# Install locally
bundle exec rake install

# Release to RubyGems (requires credentials)
bundle exec rake release
```

## Project Structure

```
vyapari/
├── lib/
│   ├── vyapari/
│   │   ├── agent.rb           # Main agent orchestrator
│   │   ├── client.rb          # Ollama API client
│   │   ├── config.rb          # Configuration utilities
│   │   ├── tools/             # Trading tools
│   │   │   ├── base.rb
│   │   │   ├── find_instrument.rb
│   │   │   ├── fetch_intraday_history.rb
│   │   │   ├── analyze_trend.rb
│   │   │   ├── fetch_expiry_list.rb
│   │   │   ├── fetch_option_chain.rb
│   │   │   ├── recommend_trade.rb
│   │   │   └── registry.rb
│   │   └── version.rb
│   ├── indicators/           # Technical indicators
│   │   ├── rsi.rb
│   │   ├── adx.rb
│   │   └── ema.rb
│   └── trading/              # Trading utilities
│       └── risk.rb
├── exe/
│   └── vyapari               # Command-line executable
├── INDICATORS.md           # Indicator documentation
└── README.md
```

## Key Design Principles

### Core Architecture Rule

**"LLM chooses the tool. Ruby supplies the arguments."**

This is the fundamental principle that ensures reliability:

- The LLM decides **WHICH** tool to call
- Ruby decides **WHAT** arguments the tool gets
- LLM-provided arguments are **completely ignored** once Ruby has context
- All parameters are auto-injected from persistent context

### Implementation Details

1. **Persistent Context Memory**:
   - All tool results are stored in `@context` hash after each execution
   - Prevents state loss between steps
   - Context keys: `instrument`, `candles`, `trend`, `expiry`, `option_chain`

2. **Argument Injection**:
   - `resolve_arguments` method completely replaces LLM arguments with context values
   - Tools receive only what Ruby determines from context
   - No empty parameters, no invented values, no guessing

3. **Tool Prerequisite Guards**:
   - `TOOL_PREREQUISITES` defines required context for each tool
   - `check_prerequisites` validates context before execution
   - Prevents 90% of invalid tool calls

4. **Hardened System Prompt**:
   - Explicit prohibition of code generation
   - Explicit prohibition of text explanations
   - "You are an autonomous trading planner" - only calls tools
   - No guessing, no inventing values

5. **Sequential Execution**:
   - Tools called one at a time
   - Results stored immediately after execution
   - Context updated before next tool call

## Troubleshooting

### Agent Not Converging

If the agent exceeds `MAX_STEPS` (8), check:
- Ollama is running and accessible
- DhanHQ credentials are valid
- Network connectivity to APIs
- Check logs for specific error messages

### Empty Parameters

If tools receive empty parameters:
- Verify context is being stored correctly
- Check `resolve_arguments` method in agent
- Ensure prerequisite tools are called first

### Infinity Errors

If you see "Infinity" errors:
- Check premium/price values are valid
- Verify position_size calculation handles zero/negative values
- Review contract data structure

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/shubhamtaywade/vyapari.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Author

**Shubham Taywade**
- Email: shubhamtaywade82@gmail.com
- GitHub: [@shubhamtaywade](https://github.com/shubhamtaywade)
