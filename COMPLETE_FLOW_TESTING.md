# Complete Flow Testing Guide

This guide shows you how to test the complete Vyapari workflow from query to final result.

## Quick Test

### Option 1: Use the Test Script (Recommended)

```bash
# Run complete flow test
bin/test_complete_flow.rb "Analyze NIFTY for options buying"

# Or with custom query
bin/test_complete_flow.rb "Analyze BANKNIFTY for options buying"
```

This script will:
1. ✅ Test Runner mode detection
2. ✅ Test system setup (registry, safety gate, agent)
3. ✅ Test global pre-check
4. ✅ Run complete workflow
5. ✅ Show phase-by-phase results
6. ✅ Display success/failure status

### Option 2: Use Debug Script (Detailed)

```bash
# Run with detailed debug output
bin/debug_workflow.rb "Analyze NIFTY for options buying"
```

This shows:
- Detailed execution trace
- Full JSON output
- Error backtraces

### Option 3: Use the Executable Directly

```bash
# Standard execution
exe/vyapari "Analyze NIFTY for options buying"

# With debug mode
DEBUG=true exe/vyapari "Analyze NIFTY for options buying"
```

## Understanding the Results

### Success Indicators

✅ **Order Executed**
- `final_status: "executed"`
- `order_id` present
- All phases completed

✅ **No Trade Recommended**
- `final_status: "no_trade"`
- Analysis completed successfully
- Market conditions didn't meet criteria

### Warning Indicators

⚠️ **Pre-check Failed**
- `final_status: "precheck_failed"`
- Usually means DhanHQ not configured
- **Expected in test mode**

⚠️ **Validation Failed**
- `final_status: "validation_failed"`
- Trade plan rejected by Agent B
- **This is good safety behavior**

### Error Indicators

❌ **Analysis Failed**
- `final_status: "analysis_failed"`
- Agent A couldn't complete analysis
- Check LLM connection and model

❌ **Execution Failed**
- `final_status: "execution_failed"`
- Agent C couldn't place order
- Check DhanHQ credentials

## Phase-by-Phase Verification

### Phase 1: Market Analysis (Agent A)

**What to check:**
```ruby
result[:phases][:analysis][:status]  # Should be "completed"
result[:phases][:analysis][:iterations]  # Should be 1-7
result[:phases][:analysis][:mtf_result]  # Should have timeframes
```

**Expected output:**
- HTF (15m) analysis
- MTF (5m) analysis
- LTF (1m) analysis
- Strike selection (options mode)
- Trade plan JSON

### Phase 2: Plan Validation (Agent B)

**What to check:**
```ruby
result[:phases][:validation][:status]  # "approved" or "rejected"
result[:phases][:validation][:reason]  # Why approved/rejected
```

**Expected output:**
- Risk calculation
- Lot size determination
- SL/TP conversion
- Executable plan OR rejection

### Phase 3: Order Execution (Agent C)

**What to check:**
```ruby
result[:phases][:execution][:status]  # "executed" or "failed"
result[:order_id]  # Order ID if executed
```

**Expected output:**
- Order ID (if executed)
- Or failure reason

## Manual Testing Steps

### Step 1: Test Individual Components

```ruby
# In Ruby console (bin/console)
require "vyapari"

# Test Runner
mode = Vyapari::Runner.detect_mode("Analyze NIFTY for options buying")
# => :options

# Test Setup
system = Vyapari::Options::CompleteIntegration.setup_system
# => {:state_machine=>..., :phased_agent=>..., ...}

# Test Pre-check
guard = Vyapari::Options::ChecklistGuard.new
precheck = guard.run_global_precheck(context: {
  market_open: true,
  event_risk: false,
  websocket_connected: true,
  dhan_authenticated: true
})
# => {:passed=>true, ...}
```

### Step 2: Test Phase 1 Only

```ruby
# Create agent
agent = Vyapari::Options::PhasedAgent.new

# Run only analysis phase
result = agent.run("Analyze NIFTY for options buying")

# Check analysis result
analysis = result[:phases][:analysis]
puts analysis[:status]
puts analysis[:mtf_result]
```

### Step 3: Test with Mock Data

```ruby
# Create agent with mock registry
registry = Ollama::Agent::ToolRegistry.new
# Register mock tools that return test data

agent = Vyapari::Options::PhasedAgent.new(registry: registry)
result = agent.run("Analyze NIFTY for options buying")
```

## Common Issues and Solutions

### Issue: "Pre-check failed"

**Solution:**
```ruby
# In test mode, provide mock context
context = {
  market_open: true,
  event_risk: false,
  websocket_connected: true,
  dhan_authenticated: true,
  in_cooldown: false,
  duplicate_position: false
}

result = agent.run(task, context: context)
```

### Issue: "Analysis failed - Stop condition met"

**Solution:**
- Check if LLM is responding
- Verify model is loaded: `docker exec -it ollama-server ollama list`
- Check Ollama URL: `ENV["OLLAMA_URL"]`
- Try different model: `ENV["OLLAMA_MODEL"] = "qwen2.5-coder:7b-instruct-q5_K_M"`

### Issue: "No LLM calls made"

**Solution:**
- Verify Ollama is running: `curl http://localhost:11434/api/version`
- Check model is available
- Verify network connectivity

## Expected Output Format

```json
{
  "workflow": "options_trading",
  "final_status": "no_trade",
  "final_output": "Higher timeframe indicates NO_TRADE: ...",
  "phases": {
    "global_precheck": {...},
    "analysis": {
      "status": "completed",
      "iterations": 5,
      "max_iterations": 7,
      "mtf_result": {
        "status": "no_trade",
        "iterations_used": 5,
        "timeframes": {
          "htf": {...},
          "mtf": {...},
          "ltf": {...}
        }
      }
    },
    "validation": {...},
    "execution": {...}
  },
  "total_llm_calls": 5
}
```

## Next Steps

1. **Run the test script** to verify basic flow
2. **Check each phase** individually if issues occur
3. **Enable debug mode** for detailed tracing
4. **Configure DhanHQ** for real trading (optional)
5. **Monitor LLM calls** to ensure within limits

## Tips

- Start with `dry_run: true` to avoid real trades
- Use `DEBUG=true` for detailed logs
- Check `result[:total_llm_calls]` stays under 12
- Verify each phase completes before moving to next
- Use the test scripts for consistent testing

