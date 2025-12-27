# frozen_string_literal: true

# Tool calling plan for multi-timeframe analysis
# Shows exactly how Agent A calls tools per timeframe

module Vyapari
  module Options
    module MTFToolPlan
      # Tool calling sequence for Options Intraday mode
      OPTIONS_INTRADAY_PLAN = {
        htf_15m: {
          iterations: 2,
          tools: [
            {
              tool: "dhan.instrument.find",
              args: { exchange_segment: "IDX_I", symbol: "NIFTY" },
              purpose: "Find NIFTY instrument"
            },
            {
              tool: "dhan.history.intraday",
              args: {
                security_id: "<from_instrument>",
                exchange_segment: "IDX_I",
                instrument: "<from_instrument>",
                interval: "15",
                from_date: "<today_minus_7_days>",
                to_date: "<today>"
              },
              purpose: "Fetch 15m OHLC for structure analysis"
            }
          ],
          analysis: "Determine regime: TREND_DAY / RANGE / VOLATILITY_EXPANSION / NO_TRADE"
        },
        mtf_5m: {
          iterations: 2,
          tools: [
            {
              tool: "dhan.history.intraday",
              args: {
                security_id: "<from_htf>",
                exchange_segment: "IDX_I",
                instrument: "<from_htf>",
                interval: "5",
                from_date: "<today_minus_3_days>",
                to_date: "<today>"
              },
              purpose: "Fetch 5m OHLC for direction and momentum"
            },
            {
              tool: "dhan.market.ltp",
              args: {
                exchange_segment: "IDX_I",
                security_id: "<from_htf>"
              },
              purpose: "Get current LTP for momentum context"
            }
          ],
          analysis: "Determine direction: BULLISH / BEARISH / NEUTRAL (must align with 15m)"
        },
        ltf_1m: {
          iterations: 2,
          tools: [
            {
              tool: "dhan.history.intraday",
              args: {
                security_id: "<from_htf>",
                exchange_segment: "IDX_I",
                instrument: "<from_htf>",
                interval: "1",
                from_date: "<today>",
                to_date: "<today>"
              },
              purpose: "Fetch 1m OHLC for entry trigger"
            }
          ],
          analysis: "Determine entry trigger and SL level (refines price only, never changes bias)"
        },
        strike_selection: {
          iterations: 2,
          tools: [
            {
              tool: "dhan.option.chain",
              args: {
                underlying_scrip: "NIFTY",
                underlying_seg: "IDX_I",
                expiry: "<from_expiry_list>"
              },
              purpose: "Get option chain with strikes, premiums, Greeks"
            },
            {
              tool: "dhan.market.ltp",
              args: {
                exchange_segment: "IDX_I",
                security_id: "<from_htf>"
              },
              purpose: "Get current spot price for ATM calculation"
            }
          ],
          analysis: "Select strike candidates based on: Direction → Regime → Momentum → Volatility → Time. Limited to ±1-2 strikes around ATM only."
        },
        synthesis: {
          iterations: 1,
          tools: [],
          analysis: "Synthesize all timeframes into final TradePlan"
        }
      }.freeze

      # Tool calling sequence for Swing Trading mode
      SWING_TRADING_PLAN = {
        htf_1d: {
          iterations: 2,
          tools: [
            {
              tool: "dhan.instrument.find",
              args: { exchange_segment: "NSE_EQ", symbol: "<stock_symbol>" },
              purpose: "Find stock instrument"
            },
            {
              tool: "dhan.history.daily",
              args: {
                security_id: "<from_instrument>",
                exchange_segment: "NSE_EQ",
                instrument: "<from_instrument>",
                from_date: "<today_minus_60_days>",
                to_date: "<today>"
              },
              purpose: "Fetch daily OHLC for primary trend"
            }
          ],
          analysis: "Determine trend: UP / DOWN / SIDEWAYS (if SIDEWAYS → NO_TRADE)"
        },
        mtf_1h: {
          iterations: 2,
          tools: [
            {
              tool: "dhan.history.intraday",
              args: {
                security_id: "<from_htf>",
                exchange_segment: "NSE_EQ",
                instrument: "<from_htf>",
                interval: "60",
                from_date: "<today_minus_30_days>",
                to_date: "<today>"
              },
              purpose: "Fetch 1H OHLC for setup formation"
            }
          ],
          analysis: "Determine setup: PULLBACK / BREAKOUT / BASE / NONE (must align with daily)"
        },
        ltf_15m: {
          iterations: 2,
          tools: [
            {
              tool: "dhan.history.intraday",
              args: {
                security_id: "<from_htf>",
                exchange_segment: "NSE_EQ",
                instrument: "<from_htf>",
                interval: "15",
                from_date: "<today_minus_7_days>",
                to_date: "<today>"
              },
              purpose: "Fetch 15m OHLC for entry zone"
            }
          ],
          analysis: "Determine entry zone and initial SL (refines entry only, never changes bias)"
        },
        synthesis: {
          iterations: 1,
          tools: [],
          analysis: "Synthesize all timeframes into final TradePlan"
        }
      }.freeze

      # Get tool plan for mode
      # @param mode [Symbol] :options_intraday or :swing_trading
      # @return [Hash] Tool calling plan
      def self.plan_for(mode)
        case mode
        when :options_intraday
          OPTIONS_INTRADAY_PLAN
        when :swing_trading
          SWING_TRADING_PLAN
        else
          raise ArgumentError, "Unknown mode: #{mode}"
        end
      end

      # Visualize tool calling sequence
      # @param mode [Symbol] Analysis mode
      # @return [String] Visual representation
      def self.visualize(mode)
        plan = plan_for(mode)

        output = <<~VISUAL
          Multi-Timeframe Tool Calling Plan (#{mode.to_s.upcase})
          =====================================================

        VISUAL

        plan.each do |phase, config|
          output += "\n#{phase.to_s.upcase} (#{config[:iterations]} iterations):\n"
          output += "  Analysis: #{config[:analysis]}\n"
          if config[:tools].any?
            output += "  Tools:\n"
            config[:tools].each_with_index do |tool_call, idx|
              output += "    #{idx + 1}. #{tool_call[:tool]}\n"
              output += "       Purpose: #{tool_call[:purpose]}\n"
              output += "       Args: #{tool_call[:args].keys.join(', ')}\n"
            end
          else
            output += "  Tools: None (synthesis phase)\n"
          end
        end

        output += "\n" + "=" * 50 + "\n"
        total_iterations = plan.values.sum { |c| c[:iterations] }
        output += "Total Iterations: #{total_iterations}\n"
        output += "Fits within budget: #{total_iterations <= 9 ? 'YES ✅' : 'NO ❌'}\n"

        output
      end
    end
  end
end

