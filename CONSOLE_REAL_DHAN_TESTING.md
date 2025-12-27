# Console Testing with Real DhanHQ API

This guide shows you how to test with actual DhanHQ API calls and continue testing even when the result is NO_TRADE.

## Quick Start with Real DhanHQ

```ruby
# In bin/console
require "vyapari/options/console_helper"

# DhanHQ is configured via environment variables:
# export CLIENT_ID=your_client_id
# export ACCESS_TOKEN=your_access_token

# Test with real DhanHQ API (continues even if NO_TRADE)
helper = Vyapari::Options::ConsoleHelper.new(
  dhan_client: dhan_client,
  continue_on_no_trade: true,
  show_tool_calls: true
)

# Test complete workflow with real API
complete = helper.test_with_real_dhan(dhan_client, "Analyze NIFTY for options buying")
```

## Testing Even When NO_TRADE

### Option 1: Continue on NO_TRADE (Default)

```ruby
helper = Vyapari::Options::ConsoleHelper.new(
  continue_on_no_trade: true  # Default: true
)

# Even if analysis returns NO_TRADE, will continue with mock plan
result = helper.test_phase_1("Analyze NIFTY for options buying")
# => Will create mock trade plan and continue to Phase 2

# Test all phases even if NO_TRADE
complete = helper.test_complete("Analyze NIFTY for options buying")
# => Will test all phases: Analysis → Validation → Execution
```

### Option 2: Force Specific Bias

```ruby
# Force BULLISH (skips real analysis, creates valid plan)
helper = Vyapari::Options::ConsoleHelper.new
result = helper.test_bullish("Analyze NIFTY for options buying")

# Force BEARISH
result = helper.test_bearish("Analyze NIFTY for options buying")
```

## Inspecting Real vs Mock Tool Calls

```ruby
helper = Vyapari::Options::ConsoleHelper.new(
  dhan_client: your_dhan_client,
  show_tool_calls: true
)

# Run workflow
complete = helper.test_complete("Analyze NIFTY for options buying")

# Inspect tool calls
helper.inspect_tool_calls(complete)
```

This will show:
- ✅ **Real API calls**: Tools that actually called DhanHQ API
- ❌ **Mock responses**: Tools that returned mock data
- 🛡️ **Safety blocks**: Tools blocked by safety gate
- 🔧 **Tool arguments**: What was passed to each tool
- 📊 **Tool responses**: What each tool returned

## Example: Real DhanHQ Testing

```ruby
# DhanHQ is configured via environment variables:
# export CLIENT_ID=your_client_id
# export ACCESS_TOKEN=your_access_token
#
# The console helper will automatically detect and configure DhanHQ

# Create helper (will auto-detect DhanHQ from ENV)
helper = Vyapari::Options::ConsoleHelper.new(
  dhan_client: dhan_client,
  continue_on_no_trade: true,
  show_tool_calls: true
)

# Test Phase 1 with real API
p1 = helper.test_phase_1("Analyze NIFTY for options buying")
# => Uses REAL DhanHQ API for market data, option chains, etc.

# Even if NO_TRADE, continue to Phase 2
if p1[:final_status] == "no_trade"
  puts "Analysis says NO_TRADE, but continuing to test Phase 2..."
  # Create mock plan to test validation
  mock_plan = helper.send(:create_valid_trade_plan, :bullish)
  p2 = helper.test_phase_2(mock_plan)
end

# Test Phase 3
p3 = helper.test_phase_3(p2[:executable_plan])
```

## Checking Tool Call Status

```ruby
helper = Vyapari::Options::ConsoleHelper.new(dhan_client: your_client)
helper.setup

# Check if DhanHQ is connected
registry = helper.instance_variable_get(:@system)[:registry]
dhan_client = helper.instance_variable_get(:@system)[:dhan_client]

if dhan_client
  puts "✅ DhanHQ connected - tools will make REAL API calls"
else
  puts "❌ DhanHQ not connected - tools will return MOCK data"
end

# List all tools
helper.list_tools
```

## Testing Individual Phases with Real API

```ruby
helper = Vyapari::Options::ConsoleHelper.new(
  dhan_client: your_dhan_client,
  continue_on_no_trade: true
)

# Phase 1: Real market analysis
p1 = helper.test_phase_1("Analyze NIFTY for options buying")
# => Uses REAL dhan.market.ltp, dhan.option.chain, etc.

# If NO_TRADE, inspect what tools were called
if p1[:final_status] == "no_trade"
  helper.inspect_tool_calls(p1)
  # Shows which tools were called and what they returned
end

# Continue to Phase 2 even if NO_TRADE
if p1[:final_status] == "no_trade" || p1[:trade_plan].nil?
  mock_plan = helper.send(:create_valid_trade_plan, :bullish)
  p2 = helper.test_phase_2(mock_plan)
  # => Tests validation phase with mock plan
end

# Continue to Phase 3
p3 = helper.test_phase_3(p2[:executable_plan])
# => Tests execution phase
```

## Understanding Tool Call Results

When you inspect tool calls, you'll see:

### Real API Call (with DhanHQ client)
```
🔧 Tool Called: dhan.market.ltp
   Args: {"exchange_segment"=>"IDX_I", "security_id"=>"13"}
   Result Status: success
   ✅ Response: {"ltp"=>22500.5, "timestamp"=>"2025-12-27T15:50:00Z"}
```

### Mock Response (without DhanHQ client)
```
🔧 Tool Called: dhan.market.ltp
   Args: {"exchange_segment"=>"IDX_I", "security_id"=>"13"}
   Result Status: success
   ✅ Response: {"ltp"=>100.0, "timestamp"=>"2025-12-27T15:50:00Z"}
   ⚠️  This is MOCK data, not real market data
```

### Safety Gate Block
```
🔧 Tool Called: dhan.order.place
   Args: {"symbol"=>"NIFTY25JAN22500CE", ...}
   Result Status: error
   ❌ Error: Safety gate blocked execution: Cannot place order without stoploss
   🛡️  Safety Errors: Cannot place order without stoploss in context
```

## Tips

1. **Always check DhanHQ connection**: Use `helper.setup` to see if client is connected
2. **Inspect tool calls**: Use `helper.inspect_tool_calls(result)` to see what actually happened
3. **Continue on NO_TRADE**: Set `continue_on_no_trade: true` to test all phases
4. **Show tool calls**: Set `show_tool_calls: true` to see calls in real-time
5. **Compare real vs mock**: Run same test with and without `dhan_client` to see the difference

## Troubleshooting

### "DhanHQ client not connected"
- Make sure you pass `dhan_client: your_client` when creating helper
- Check that your DhanHQ client is properly initialized
- Verify API credentials are correct

### "Tools still returning mock data"
- Check `helper.setup` output - should show "✅ Connected"
- Verify `dhan_client` is passed to `ToolRegistryAdapter`
- Check tool handler implementation

### "NO_TRADE stops workflow"
- Set `continue_on_no_trade: true` (default)
- Or use `test_bullish`/`test_bearish` to force valid plans
- Or manually create trade plan and continue

