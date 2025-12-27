# Swing Trading Universe Tool

The `fetch_universe` tool downloads and parses NSE index CSVs to build a curated list of stocks suitable for swing trading.

## Features

- **Downloads from NSE**: Fetches real-time index constituents from NSE official URLs
- **Multiple Indices**: Supports Nifty50, Nifty100, Nifty200, Midcap, Smallcap, and sector indices
- **Automatic Deduplication**: Combines multiple indices and removes duplicates
- **Symbol Cleaning**: Removes exchange suffixes (-EQ, -BE, etc.) automatically
- **Error Handling**: Gracefully handles network failures and continues with available data

## Supported Indices

- `nifty50` - Nifty 50 (Large cap)
- `nifty_next50` - Nifty Next 50
- `nifty100` - Nifty 100
- `nifty200` - Nifty 200
- `nifty_midcap150` - Nifty Midcap 150
- `nifty_midcap100` - Nifty Midcap 100
- `nifty_smallcap250` - Nifty Smallcap 250
- `nifty_bank` - Nifty Bank
- `nifty_it` - Nifty IT
- `nifty_pharma` - Nifty Pharma

## Usage

### Via CLI (Swing Mode)

```bash
# Fetch combined universe from all indices
./exe/vyapari "swing trading ideas"

# The agent will automatically call fetch_universe tool
```

### Programmatically

```ruby
require "vyapari"

# Direct tool usage
tool = Vyapari::Tools::Swing::FetchUniverse.new

# Fetch combined universe (all indices)
result = tool.call({})
# => {
#   "universe" => ["RELIANCE", "HDFCBANK", "TCS", ...],
#   "source" => "combined",
#   "count" => 850
# }

# Fetch specific index
result = tool.call({ "index_filter" => "nifty50" })
# => {
#   "universe" => ["RELIANCE", "HDFCBANK", ...],
#   "source" => "nifty50",
#   "count" => 50
# }
```

### Via Swing Agent

```ruby
require "vyapari"

agent = Vyapari::Swing::Agent.new
result = agent.run("fetch swing universe")
# Agent will call fetch_universe tool and return results
```

## Tool Schema

```json
{
  "name": "fetch_universe",
  "description": "Fetches the swing trading universe (list of stock symbols) from NSE index constituents.",
  "parameters": {
    "type": "object",
    "properties": {
      "index_filter": {
        "type": "string",
        "description": "Optional: Filter by specific index (nifty50, nifty100, etc.)",
        "enum": ["nifty50", "nifty_next50", "nifty100", ...]
      }
    },
    "required": []
  }
}
```

## Response Format

```json
{
  "universe": ["RELIANCE", "HDFCBANK", "TCS", "INFY", ...],
  "source": "combined" | "nifty50" | "nifty100" | ...,
  "count": 850
}
```

## Error Handling

If download fails, the tool returns:

```json
{
  "error": "HTTP 404" | "Network timeout" | ...,
  "universe": [],
  "count": 0
}
```

## Implementation Details

- **Network Timeout**: 60 seconds read timeout, 30 seconds connection timeout
- **Retry Logic**: 2 retries with exponential backoff (2s, 4s)
- **User Agent**: Uses browser-like user agent to avoid blocking
- **Symbol Normalization**: Automatically removes exchange suffixes
- **Case Insensitive**: All symbols are normalized to uppercase

## Example Workflow

1. Agent calls `fetch_universe` with empty params `{}`
2. Tool downloads CSVs from all NSE indices
3. Parses and deduplicates symbols
4. Returns sorted array of unique symbols
5. Agent stores in context for further analysis

## Notes

- Downloads happen in real-time (no caching by default)
- For production, consider adding caching layer
- Network-dependent: Requires internet connection
- Rate limiting: NSE may throttle if too many requests

