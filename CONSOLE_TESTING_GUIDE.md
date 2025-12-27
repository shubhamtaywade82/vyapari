# Console Testing Guide

This guide shows you how to test each phase of Vyapari individually in the Ruby console, with separate examples for BULLISH and BEARISH trades.

## Starting the Console

```bash
bin/console
```

## Quick Start

```ruby
# Load the helper
require "vyapari/options/console_helper"

# Create helper instance
helper = Vyapari::Options::ConsoleHelper.new

# Test with BULLISH bias (forces valid trade plan)
result = helper.test_bullish("Analyze NIFTY for options buying")

# Test with BEARISH bias (forces valid trade plan)
result = helper.test_bearish("Analyze NIFTY for options buying")

# Test complete workflow with BULLISH bias
complete = helper.test_complete_bullish("Analyze NIFTY for options buying")

# Test complete workflow with BEARISH bias
complete = helper.test_complete_bearish("Analyze NIFTY for options buying")

# Or test with real market analysis (may return NO_TRADE)
result = helper.test_phase_1("Analyze NIFTY for options buying")
```

## Testing BULLISH Trades

### Complete BULLISH Workflow

```ruby
require "vyapari/options/console_helper"
helper = Vyapari::Options::ConsoleHelper.new

# Test complete BULLISH workflow (all phases)
complete_bull = helper.test_complete_bullish("Analyze NIFTY for options buying")

# Inspect results
complete_bull[:final_status]    # => "test_completed" or "executed"
complete_bull[:order_id]        # => Order ID
complete_bull[:trade_plan]      # => BULLISH trade plan
complete_bull[:phases]          # => All phase results
```

### BULLISH Phase-by-Phase

```ruby
# Phase 1: Market Analysis (BULLISH)
p1_bull = helper.test_bullish("Analyze NIFTY for options buying")
# => Creates valid BULLISH trade plan

# Inspect BULLISH trade plan
p1_bull[:trade_plan][:bias]              # => "BULLISH"
p1_bull[:trade_plan][:strike_selection][:preferred_type]  # => "CE"
p1_bull[:trade_plan][:htf][:regime]      # => "TREND_DAY"
p1_bull[:trade_plan][:mtf][:direction]   # => "BULLISH"
p1_bull[:trade_plan][:mtf][:momentum]    # => "STRONG"

# Phase 2: Plan Validation (BULLISH)
p2_bull = helper.test_phase_2(p1_bull[:trade_plan])
# => Validates BULLISH plan, creates executable plan

# Inspect executable plan
exec_plan = p2_bull[:executable_plan]
exec_plan[:execution_plan][:type]         # => "CE"
exec_plan[:execution_plan][:strike]       # => 22500

# Phase 3: Order Execution (BULLISH)
p3_bull = helper.test_phase_3(exec_plan)
# => Executes BULLISH order

# Inspect execution result
p3_bull[:status]              # => "executed"
p3_bull[:order_id]            # => Order ID
```

### BULLISH MTF Analysis

```ruby
# Test BULLISH with MTF breakdown
result = helper.test_bullish("Analyze NIFTY for options buying")

# Access MTF results
mtf = result[:phases][:analysis][:mtf_result]
mtf[:timeframes][:htf][:regime]        # => "TREND_DAY"
mtf[:timeframes][:mtf][:direction]     # => "BULLISH"
mtf[:timeframes][:mtf][:momentum]      # => "STRONG"
mtf[:timeframes][:ltf][:entry_type]    # => "BREAKOUT"
mtf[:timeframes][:strike_selection]     # => Strike candidates
```

## Testing BEARISH Trades

### Complete BEARISH Workflow

```ruby
require "vyapari/options/console_helper"
helper = Vyapari::Options::ConsoleHelper.new

# Test complete BEARISH workflow (all phases)
complete_bear = helper.test_complete_bearish("Analyze NIFTY for options buying")

# Inspect results
complete_bear[:final_status]    # => "test_completed" or "executed"
complete_bear[:order_id]        # => Order ID
complete_bear[:trade_plan]      # => BEARISH trade plan
complete_bear[:phases]          # => All phase results
```

### BEARISH Phase-by-Phase

```ruby
# Phase 1: Market Analysis (BEARISH)
p1_bear = helper.test_bearish("Analyze NIFTY for options buying")
# => Creates valid BEARISH trade plan

# Inspect BEARISH trade plan
p1_bear[:trade_plan][:bias]              # => "BEARISH"
p1_bear[:trade_plan][:strike_selection][:preferred_type]  # => "PE"
p1_bear[:trade_plan][:htf][:regime]      # => "TREND_DAY"
p1_bear[:trade_plan][:mtf][:direction]   # => "BEARISH"
p1_bear[:trade_plan][:mtf][:momentum]    # => "STRONG"

# Phase 2: Plan Validation (BEARISH)
p2_bear = helper.test_phase_2(p1_bear[:trade_plan])
# => Validates BEARISH plan, creates executable plan

# Inspect executable plan
exec_plan = p2_bear[:executable_plan]
exec_plan[:execution_plan][:type]         # => "PE"
exec_plan[:execution_plan][:strike]       # => 22500

# Phase 3: Order Execution (BEARISH)
p3_bear = helper.test_phase_3(exec_plan)
# => Executes BEARISH order

# Inspect execution result
p3_bear[:status]              # => "executed"
p3_bear[:order_id]            # => Order ID
```

### BEARISH MTF Analysis

```ruby
# Test BEARISH with MTF breakdown
result = helper.test_bearish("Analyze NIFTY for options buying")

# Access MTF results
mtf = result[:phases][:analysis][:mtf_result]
mtf[:timeframes][:htf][:regime]        # => "TREND_DAY"
mtf[:timeframes][:mtf][:direction]     # => "BEARISH"
mtf[:timeframes][:mtf][:momentum]      # => "STRONG"
mtf[:timeframes][:ltf][:entry_type]    # => "BREAKOUT"
mtf[:timeframes][:strike_selection]     # => Strike candidates (PE)
```

## Comparing BULLISH vs BEARISH

```ruby
helper = Vyapari::Options::ConsoleHelper.new

# Test both side by side
bull_result = helper.test_bullish("Analyze NIFTY for options buying")
bear_result = helper.test_bearish("Analyze NIFTY for options buying")

# Compare trade plans
bull_plan = bull_result[:trade_plan]
bear_plan = bear_result[:trade_plan]

puts "BULLISH:"
puts "  Type: #{bull_plan[:strike_selection][:preferred_type]}"  # => "CE"
puts "  Direction: #{bull_plan[:mtf][:direction]}"              # => "BULLISH"
puts "  Entry: #{bull_plan[:ltf][:trigger]}"                      # => "Price breaks above..."

puts "BEARISH:"
puts "  Type: #{bear_plan[:strike_selection][:preferred_type]}"  # => "PE"
puts "  Direction: #{bear_plan[:mtf][:direction]}"              # => "BEARISH"
puts "  Entry: #{bear_plan[:ltf][:trigger]}"                    # => "Price breaks below..."
```

## Detailed Examples

### 1. Setup System

```ruby
require "vyapari/options/console_helper"
helper = Vyapari::Options::ConsoleHelper.new

# Setup (run once)
helper.setup
```

### 2. Test Phase 1: Market Analysis

```ruby
# Test with BULLISH bias (forces valid trade plan)
result = helper.test_bullish("Analyze NIFTY for options buying")

# Test with BEARISH bias (forces valid trade plan)
result = helper.test_bearish("Analyze NIFTY for options buying")

# Test with real market analysis (may return NO_TRADE)
result = helper.test_phase_1("Analyze NIFTY for options buying")

# Force specific bias
result = helper.test_phase_1("Analyze NIFTY for options buying", force_bias: :bullish)
result = helper.test_phase_1("Analyze NIFTY for options buying", force_bias: :bearish)

# Inspect the result
result[:final_status]        # => "completed" or "no_trade"
result[:trade_plan]          # => Trade plan hash
result[:phases][:analysis]   # => Detailed analysis result

# Access MTF results
mtf = result[:phases][:analysis][:mtf_result]
mtf[:timeframes][:htf]       # => Higher timeframe analysis
mtf[:timeframes][:mtf]       # => Mid timeframe analysis
mtf[:timeframes][:ltf]       # => Lower timeframe analysis
```

### 3. Test Individual MTF Timeframes

```ruby
# Test Higher Timeframe (15m) only
htf = helper.test_mtf_htf("Analyze NIFTY for options buying")

# Test Mid Timeframe (5m) only
mtf = helper.test_mtf_mtf("Analyze NIFTY for options buying")

# Test Lower Timeframe (1m) only
ltf = helper.test_mtf_ltf("Analyze NIFTY for options buying")
```

### 4. Test Phase 2: Plan Validation

```ruby
# Option 1: Provide trade plan from Phase 1
phase1_result = helper.test_phase_1("Analyze NIFTY for options buying")
validation = helper.test_phase_2(phase1_result[:trade_plan])

# Option 2: Let it run Phase 1 automatically
validation = helper.test_phase_2

# Inspect validation result
validation[:status]          # => "approved" or "rejected"
validation[:reason]          # => Reason for approval/rejection
```

### 5. Test Phase 3: Order Execution

```ruby
# Option 1: Provide executable plan from Phase 2
phase1_result = helper.test_phase_1("Analyze NIFTY for options buying")
phase2_result = helper.test_phase_2(phase1_result[:trade_plan])
execution = helper.test_phase_3(phase2_result[:executable_plan])

# Option 2: Let it run Phases 1 & 2 automatically
execution = helper.test_phase_3

# Inspect execution result
execution[:status]           # => "executed" or "failed"
execution[:order_id]          # => Order ID if executed
execution[:reason]            # => Reason if failed
```

### 6. Test Complete Workflow

```ruby
# Test all phases in sequence
complete = helper.test_complete("Analyze NIFTY for options buying")

# Inspect complete result
complete[:final_status]       # => Final status
complete[:order_id]           # => Order ID if executed
complete[:phases]             # => All phase results
```

### 7. Inspect System State

```ruby
# Check current state machine state
helper.inspect_state

# List available tools
helper.list_tools
```

## Advanced Usage

### Test Mode

```ruby
# Enable test mode (continues even if NO_TRADE)
helper = Vyapari::Options::ConsoleHelper.new(test_mode: true)
result = helper.test_phase_1("Analyze NIFTY for options buying")
```

### Dry Run vs Real Trading

```ruby
# Dry run (default)
helper = Vyapari::Options::ConsoleHelper.new(dry_run: true)

# Real trading (WARNING: Will place real orders!)
helper = Vyapari::Options::ConsoleHelper.new(dry_run: false)
```

### Access Internal Objects

```ruby
# Get the phased agent
agent = helper.instance_variable_get(:@agent)

# Get state machine
sm = helper.instance_variable_get(:@system)[:state_machine]

# Get tool registry
registry = helper.instance_variable_get(:@system)[:registry]

# Get MTF agent
mtf_agent = agent.instance_variable_get(:@mtf_agent)
```

### Manual Phase Execution

```ruby
# Setup first
helper.setup
agent = helper.instance_variable_get(:@agent)

# Manually run analysis phase
analysis_result = agent.send(:run_analysis_phase, "Analyze NIFTY for options buying")

# Extract trade plan
trade_plan = agent.send(:extract_trade_plan, analysis_result)

# Manually run validation phase
validation_result = agent.send(:run_validation_phase, trade_plan)

# Extract executable plan
executable_plan = agent.send(:extract_executable_plan, validation_result)

# Manually run execution phase
execution_result = agent.send(:run_execution_phase, executable_plan)
```

## Common Patterns

### Test with Custom Context

```ruby
helper.setup
agent = helper.instance_variable_get(:@agent)

custom_context = {
  market_open: true,
  event_risk: false,
  websocket_connected: true,
  dhan_authenticated: true,
  in_cooldown: false,
  duplicate_position: false,
  account_balance: 100_000,
  max_risk_percent: 1.0
}

result = agent.run("Analyze NIFTY for options buying", context: custom_context)
```

### Debug Specific Phase

```ruby
# Enable debug logging
ENV["DEBUG"] = "true"
ENV["VYAPARI_LOG_LEVEL"] = "DEBUG"

helper = Vyapari::Options::ConsoleHelper.new
result = helper.test_phase_1("Analyze NIFTY for options buying")
```

### Inspect Tool Calls

```ruby
helper.setup
agent = helper.instance_variable_get(:@agent)

# Run phase and inspect tool calls
result = helper.test_phase_1("Analyze NIFTY for options buying")

# Check what tools were called
analysis = result[:phases][:analysis]
if analysis[:context]
  analysis[:context].each do |item|
    if item[:tool_call]
      puts "Tool: #{item[:tool_call][:tool]}"
      puts "Args: #{item[:tool_call][:args]}"
      puts "Result: #{item[:result]}"
    end
  end
end
```

## Tips

1. **Always setup first**: Run `helper.setup` before testing phases
2. **Use test mode for development**: `test_mode: true` allows testing even when market says NO_TRADE
3. **Inspect intermediate results**: Check `result[:phases]` to see what each phase produced
4. **Use debug mode**: Set `ENV["DEBUG"] = "true"` for detailed logging
5. **Test individual timeframes**: Use `test_mtf_htf`, `test_mtf_mtf`, `test_mtf_ltf` to debug MTF analysis

## Troubleshooting

### "MTF Agent not found"
- Make sure you've run `helper.setup` first
- The MTF agent is created during agent initialization

### "No trade plan produced"
- Market analysis may have returned NO_TRADE
- Try with `test_mode: true` to force continuation
- Check the analysis result for details

### "No executable plan produced"
- Validation phase may have rejected the trade plan
- Check validation result for rejection reason
- Ensure trade plan has all required fields

