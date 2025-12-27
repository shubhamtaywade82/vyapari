# Vyapari

**Vyapari** is an AI-powered options trading agent built in Ruby that uses Large Language Models (LLMs) via Ollama to analyze market trends and recommend option trading strategies. It integrates with the DhanHQ API to fetch real-time market data, calculate technical indicators (including volume-based indicators), and generate trade recommendations.

## Table of Contents

- [Features](#features)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Usage](#usage)
- [Architecture](#architecture)
- [Technical Indicators](#technical-indicators)
- [Development Guide](#development-guide)
- [Contributing](#contributing)
- [Project Structure](#project-structure)
- [Troubleshooting](#troubleshooting)
- [License](#license)

## Features

- 🤖 **AI-Powered Agent**: Uses Ollama LLM to orchestrate trading analysis workflow
- 📊 **Technical Analysis**: Calculates RSI, ADX, EMA, and volume indicators (MFI, CMF, OBV) for trend analysis
- 📈 **Options Trading**: Fetches option chains and recommends trades based on market trends
- 🔄 **Context-Aware**: Maintains persistent context across tool calls to prevent state loss
- 🛡️ **Robust Error Handling**: Validates prerequisites, injects arguments from context, and prevents invalid tool calls
- 📝 **Comprehensive Logging**: Detailed logs for debugging and monitoring agent execution
- 📦 **Volume Indicators**: Uses `technical-analysis` and `ruby-technical-analysis` libraries for comprehensive indicator support
- 🎯 **Multi-Timeframe Analysis**: Analyzes 15-minute structure and 5-minute trends for better accuracy

## Installation

### Prerequisites

- Ruby >= 3.2.0
- Ollama installed and running (default: `http://localhost:11434`)
- DhanHQ API credentials

### Setup

1. **Clone the repository:**
```bash
git clone https://github.com/shubhamtaywade/vyapari.git
cd vyapari
```

2. **Install dependencies:**
```bash
bundle install
```

3. **Set up environment variables** (create `.env` file):
```bash
# Ollama Configuration
OLLAMA_URL=http://localhost:11434  # Optional, defaults to localhost:11434

# DhanHQ API Configuration
CLIENT_ID=your_client_id
ACCESS_TOKEN=your_access_token
DHAN_LOG_LEVEL=INFO  # Optional, defaults to INFO
```

4. **Run the setup script:**
```bash
bin/setup
```

## Quick Start

### Command Line

The simplest way to use Vyapari is via the command-line executable:

```bash
exe/vyapari "Analyze NIFTY index on multi timeframe options buying"
```

### Programmatic Usage

```ruby
require "vyapari"

# Configure DhanHQ (if not already configured)
Vyapari::Config.configure_dhan!

# Create and run the agent
agent = Vyapari::Options::Agent.new
result = agent.run("NIFTY options buying")

puts result
```

## Usage

### Options Trading Mode (Default)

The agent follows a strict sequential workflow:

1. **Find Instrument** → Locates the trading instrument (NIFTY, BANKNIFTY, stocks, etc.)
2. **Fetch 15m History** → Retrieves 15-minute candles for structure analysis
3. **Analyze Structure** → Detects HH/HL (bullish) or LL/LH (bearish) patterns
4. **Fetch 5m History** → Retrieves 5-minute candles for trend analysis
5. **Analyze Trend** → Calculates indicators and determines trend (bullish/bearish/avoid)
6. **Fetch Expiry List** → Gets available option expiry dates
7. **Fetch Option Chain** → Retrieves option chain data (only if trend is bullish/bearish)
8. **Recommend Trade** → Generates trade recommendation

### Swing Trading Mode

```bash
exe/vyapari "swing trading ideas"
```

The swing agent:
- Fetches universe from NSE indices
- Analyzes technical indicators
- Filters and ranks candidates
- Provides swing trading recommendations

## Architecture

Vyapari follows a multi-layered architecture:

### 1. Agent Layer (`Vyapari::Options::Agent` / `Vyapari::Swing::Agent`)

Orchestrates the LLM interaction and tool execution:
- Manages message history and context
- Enforces tool prerequisites
- Injects arguments from context
- Prevents LLM hallucination and code generation
- Auto-injects critical tools after multiple failures

### 2. Tool Layer (`Vyapari::Tools`)

Modular tools for trading operations:

**Options Trading Tools:**
- `FindInstrument`: Locates trading instruments
- `FetchIntradayHistory`: Retrieves historical price data (5m, 15m intervals)
- `AnalyzeStructure15m`: Analyzes 15-minute market structure (HH/HL, LL/LH)
- `AnalyzeTrend`: Calculates technical indicators and determines market trend
- `FetchExpiryList`: Gets available option expiry dates
- `FetchOptionChain`: Retrieves option chain data
- `RecommendTrade`: Generates trade recommendations

**Swing Trading Tools:**
- `FetchUniverse`: Downloads NSE index constituents
- `AnalyzeSwingTechnicals`: Analyzes stocks for swing trading
- `BatchAnalyzeUniverse`: Batch processes multiple stocks

### 3. Indicator Layer (`Vyapari::Indicators`)

Technical analysis calculations:

**Custom Implementations:**
- `RSI`: Relative Strength Index
- `ADX`: Average Directional Index
- `EMA`: Exponential Moving Average
- `Supertrend`: Supertrend indicator

**Library-Based (via `TechnicalAnalysisAdapter`):**
- Volume indicators: OBV, CMF, MFI, VROC, A/D, VPT, VWAP
- Price indicators: RSI, MACD, Bollinger Bands, Stochastic, ATR, CCI, Williams %R
- Unique indicators: IMI, Chande Momentum Oscillator, Volume Oscillator, Pivot Points

### 4. Trading Layer (`Vyapari::Trading`)

Risk management utilities:
- Position sizing calculations
- Risk management rules

## Technical Indicators

### Price-Based Indicators

#### RSI (Relative Strength Index)
- **Range**: 0-100
- **Purpose**: Measures momentum
- **Interpretation**:
  - >70: Overbought (potential sell signal)
  - <30: Oversold (potential buy signal)
  - 30-70: Neutral zone
- **Default Period**: 14

#### ADX (Average Directional Index)
- **Range**: 0-100
- **Purpose**: Measures trend strength (not direction)
- **Interpretation**:
  - <20: Weak/no trend (choppy market)
  - 20-25: Developing trend
  - >25: Strong trend
  - >50: Very strong trend (rare)
- **Default Period**: 14
- **Usage**: Primary filter - ADX > 25 required for bullish/bearish signals

#### EMA (Exponential Moving Average)
- **Periods**: 9 (fast) and 21 (slow)
- **Purpose**: Identifies trend direction
- **Interpretation**:
  - Fast > Slow: Uptrend (bullish)
  - Fast < Slow: Downtrend (bearish)
  - Fast ≈ Slow: Sideways/choppy market

### Volume-Based Indicators

#### MFI (Money Flow Index)
- **Range**: 0-100
- **Purpose**: Volume-weighted RSI
- **Interpretation**:
  - >80: Overbought
  - <20: Oversold
  - >50: Buying pressure
  - <50: Selling pressure

#### CMF (Chaikin Money Flow)
- **Range**: -1 to +1
- **Purpose**: Volume-weighted accumulation/distribution
- **Interpretation**:
  - >0: Buying pressure (bullish)
  - <0: Selling pressure (bearish)
  - >0.25: Strong buying pressure
  - <-0.25: Strong selling pressure

#### OBV (On-Balance Volume)
- **Purpose**: Cumulative volume indicator
- **Interpretation**:
  - Rising OBV: Buying pressure (bullish)
  - Falling OBV: Selling pressure (bearish)
  - OBV divergence: Potential reversal signal

### Trend Determination Logic

```ruby
# Price-based trend
price_trend = if ADX > 25 && EMA_Fast > EMA_Slow
  "bullish"
elsif ADX > 25 && EMA_Fast < EMA_Slow
  "bearish"
else
  "avoid"  # ADX ≤ 25 = choppy market
end

# Volume confirmation
final_trend = if price_trend == "bullish" && volume_trend == "bullish"
  "bullish"  # Strong confirmation
elsif price_trend == "bearish" && volume_trend == "bearish"
  "bearish"  # Strong confirmation
elsif price_trend == "bullish" && volume_trend == "bearish"
  "avoid"  # Volume divergence - weak signal
else
  price_trend  # Use price trend if volume is neutral
end
```

### Indicator Libraries

Vyapari uses two technical analysis libraries:

1. **intrinio/technical-analysis** (Primary)
   - 40+ indicators
   - Comprehensive coverage
   - Used for 95% of indicators

2. **ruby-technical-analysis** (Unique Indicators)
   - IMI, Chande Momentum Oscillator, Volume Oscillator, Pivot Points
   - Used only when indicator is not available in intrinio

See [INDICATORS_COMPARISON.md](INDICATORS_COMPARISON.md) for complete indicator mapping.

## Development Guide

### Project Structure

```
vyapari/
├── lib/
│   ├── vyapari/
│   │   ├── agent.rb                    # Base agent class
│   │   ├── client.rb                   # Ollama API client
│   │   ├── config.rb                   # Configuration utilities
│   │   ├── runner.rb                   # Mode router (options/swing)
│   │   ├── options/
│   │   │   └── agent.rb               # Options trading agent
│   │   ├── swing/
│   │   │   └── agent.rb               # Swing trading agent
│   │   ├── tools/                     # Trading tools
│   │   │   ├── base.rb
│   │   │   ├── find_instrument.rb
│   │   │   ├── fetch_intraday_history.rb
│   │   │   ├── analyze_structure_15m.rb
│   │   │   ├── analyze_trend.rb
│   │   │   ├── fetch_expiry_list.rb
│   │   │   ├── fetch_option_chain.rb
│   │   │   ├── recommend_trade.rb
│   │   │   ├── registry.rb
│   │   │   └── swing/                 # Swing trading tools
│   │   └── indicators/                # Technical indicators
│   │       ├── rsi.rb                 # Custom RSI
│   │       ├── adx.rb                 # Custom ADX
│   │       ├── ema.rb                 # Custom EMA
│   │       ├── technical_analysis_adapter.rb  # Library adapter
│   │       └── volume_indicators.rb   # Volume helper module
│   └── trading/
│       └── risk.rb                    # Risk management
├── exe/
│   └── vyapari                        # CLI executable
├── spec/                              # RSpec tests
├── INDICATORS.md                      # Indicator documentation
├── INDICATORS_COMPARISON.md           # Library comparison
├── VOLUME_INDICATORS.md               # Volume indicators guide
├── SWING_UNIVERSE.md                  # Swing trading docs
└── README.md                          # This file
```

### Key Design Principles

#### Core Architecture Rule

**"LLM chooses the tool. Ruby supplies the arguments."**

This fundamental principle ensures reliability:
- The LLM decides **WHICH** tool to call
- Ruby decides **WHAT** arguments the tool gets
- LLM-provided arguments are **completely ignored** once Ruby has context
- All parameters are auto-injected from persistent context

#### Implementation Details

1. **Persistent Context Memory**:
   - All tool results stored in `@context` hash after each execution
   - Prevents state loss between steps
   - Context keys: `instrument`, `candles`, `candles_15m`, `structure_15m`, `trend`, `expiry`, `option_chain`

2. **Argument Injection**:
   - `resolve_arguments` method replaces LLM arguments with context values
   - Tools receive only what Ruby determines from context
   - No empty parameters, no invented values, no guessing

3. **Tool Prerequisite Guards**:
   - `TOOL_PREREQUISITES` defines required context for each tool
   - `check_prerequisites` validates context before execution
   - Prevents invalid tool calls

4. **Auto-Injection for Critical Tools**:
   - After 3 failed attempts, critical tools (`analyze_trend`, `fetch_expiry_list`, `analyze_structure_15m`) are auto-injected
   - Prevents infinite loops when LLM fails to call tools

5. **Sequential Execution**:
   - Tools called one at a time
   - Results stored immediately after execution
   - Context updated before next tool call

### Running Tests

```bash
# Run RSpec tests
bundle exec rspec

# Run with coverage
COVERAGE=true bundle exec rspec

# Run specific test file
bundle exec rspec spec/vyapari/tools/analyze_trend_spec.rb
```

### Code Quality

```bash
# Run RuboCop
bundle exec rubocop

# Auto-fix issues
bundle exec rubocop -a

# Check specific file
bundle exec rubocop lib/vyapari/options/agent.rb
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

### Adding New Indicators

1. **Using Library Indicators:**
```ruby
# In lib/vyapari/indicators/technical_analysis_adapter.rb
def new_indicator(period: 14)
  return nil if @intrinio_data.length < period
  begin
    TechnicalAnalysis::NewIndicator.calculate(@intrinio_data, period: period)
  rescue ArgumentError
    nil
  end
end
```

2. **Custom Implementation:**
```ruby
# Create lib/vyapari/indicators/new_indicator.rb
module Vyapari
  module Indicators
    class NewIndicator
      def self.calculate(data, period: 14)
        # Your calculation logic
      end
    end
  end
end
```

### Adding New Tools

1. **Create the tool:**
```ruby
# lib/vyapari/tools/new_tool.rb
module Vyapari
  module Tools
    class NewTool < Base
      def self.name = "new_tool"

      def self.schema
        {
          type: "function",
          function: {
            name: name,
            description: "Tool description",
            parameters: {
              type: "object",
              properties: {},
              required: []
            }
          }
        }
      end

      def call(p)
        # Tool implementation
      end
    end
  end
end
```

2. **Register the tool:**
```ruby
# In agent's default_registry method
registry.register(Tools::NewTool)
```

3. **Add to prerequisites:**
```ruby
TOOL_PREREQUISITES = {
  "new_tool" => [:required_context_key]
}
```

4. **Add argument resolution:**
```ruby
# In resolve_arguments method
when "new_tool"
  raise "Missing context" unless @context[:required_context_key]
  { "param" => @context[:required_context_key] }
```

5. **Add context storage:**
```ruby
# In store_in_context method
when "new_tool"
  @context[:result_key] = result
```

## Contributing

We welcome contributions! Please follow these guidelines:

### Getting Started

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes
4. Write/update tests
5. Ensure all tests pass: `bundle exec rspec`
6. Run linter: `bundle exec rubocop`
7. Commit your changes: `git commit -am 'Add new feature'`
8. Push to the branch: `git push origin feature/my-feature`
9. Submit a pull request

### Code Style

- Follow Ruby style guide
- Run RuboCop before committing
- Write tests for new features
- Update documentation for API changes

### Testing Guidelines

- Write unit tests for all new tools
- Test error cases and edge conditions
- Mock external API calls
- Ensure tests are deterministic

### Documentation

- Update README.md for user-facing changes
- Add code comments for complex logic
- Update relevant .md files (INDICATORS.md, etc.)
- Keep examples up to date

### Pull Request Process

1. Ensure all tests pass
2. Update CHANGELOG.md
3. Add/update documentation
4. Request review from maintainers
5. Address review feedback
6. Maintainers will merge after approval

See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for our code of conduct.

## Configuration

### Ollama Configuration

Set the Ollama URL via environment variable:
```bash
export OLLAMA_URL=http://localhost:11434
```

Or pass a custom client to the agent:
```ruby
client = Vyapari::Client.new(url: "http://custom-ollama:11434")
agent = Vyapari::Options::Agent.new(client: client)
```

### DhanHQ Configuration

DhanHQ is configured via environment variables:
- `CLIENT_ID`: Your DhanHQ client ID
- `ACCESS_TOKEN`: Your DhanHQ access token
- `DHAN_LOG_LEVEL`: Logging level (default: INFO)

Configure programmatically:
```ruby
Vyapari::Config.configure_dhan!
```

### Logging

Set log level via environment variable:
```bash
export VYAPARI_LOG_LEVEL=DEBUG  # DEBUG, INFO, WARN, ERROR
```

## Troubleshooting

### Agent Not Converging

If the agent exceeds `MAX_STEPS` (15), check:
- Ollama is running and accessible
- DhanHQ credentials are valid
- Network connectivity to APIs
- Check logs for specific error messages
- Verify all required tools are being called

### Volume Indicator Errors

If you see "wrong number of arguments" errors:
- Volume indicators are wrapped in error handling
- Analysis continues with price-based indicators only
- Check that candles include volume data
- Verify technical-analysis library is installed: `bundle install`

### Missing Context Errors

If tools report missing context:
- Verify prerequisite tools are called first
- Check `store_in_context` is updating context correctly
- Ensure workflow is followed sequentially
- Review logs to see which tool failed

### LLM Refusing to Provide Analysis

The agent is configured to provide insights based on available facts. If you see generic refusals:
- The system prompt explicitly requires analysis
- Tool results are automatically formatted
- Final response should include all analysis results
- Check that `recommend_trade` was called successfully

### Empty Parameters

If tools receive empty parameters:
- Verify context is being stored correctly
- Check `resolve_arguments` method in agent
- Ensure prerequisite tools are called first
- Review context hash contents in logs

## Additional Documentation

- [INDICATORS.md](INDICATORS.md) - Detailed indicator documentation
- [INDICATORS_COMPARISON.md](INDICATORS_COMPARISON.md) - Library comparison and indicator mapping
- [VOLUME_INDICATORS.md](VOLUME_INDICATORS.md) - Volume indicators usage guide
- [SWING_UNIVERSE.md](SWING_UNIVERSE.md) - Swing trading universe documentation
- [CHANGELOG.md](CHANGELOG.md) - Version history

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Author

**Shubham Taywade**
- Email: shubhamtaywade82@gmail.com
- GitHub: [@shubhamtaywade](https://github.com/shubhamtaywade)

## Acknowledgments

- [DhanHQ](https://dhanhq.com/) for market data API
- [Ollama](https://ollama.ai/) for LLM infrastructure
- [intrinio/technical-analysis](https://github.com/intrinio/technical-analysis) for comprehensive indicators
- [ruby-technical-analysis](https://github.com/johnnypaper/ruby-technical-analysis) for unique indicators
