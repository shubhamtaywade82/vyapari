# frozen_string_literal: true

require_relative "../tool_registry"
require "date"
require "time"
require_relative "../../../vyapari/trading_calendar"

module Ollama
  class Agent
    # Tools namespace
    module Tools
      # Complete DhanHQ toolset with formal tool contracts
      # LLM never talks to DhanHQ directly - only through these tools
      class DhanTools
        def self.register_all(registry:, dhan_client: nil, cache_store: nil)
          register_market_data_tools(registry, dhan_client)
          register_historical_tools(registry, dhan_client)
          register_account_tools(registry, dhan_client)
          register_trading_tools(registry, dhan_client)
          register_super_order_tools(registry, dhan_client)
          register_cache_tools(registry, cache_store)
        end

        # ============================================
        # MARKET DATA TOOLS (READ-ONLY)
        # ============================================

        def self.register_market_data_tools(registry, dhan_client)
          # 1. Instrument Lookup
          registry.register(
            descriptor: {
              name: "dhan.instrument.find",
              category: "market",
              description: "Finds an instrument and its trading metadata by symbol and exchange",
              when_to_use: "When resolving symbols before analysis or trading",
              when_not_to_use: "If security_id already known from context",
              risk_level: :none,
              dependencies: {
                required_tools: [],
                required_outputs: [],
                produces: ["instrument"]
              },
              inputs: {
                type: "object",
                properties: {
                  exchange_segment: {
                    type: "string",
                    description: "Exchange segment (e.g., 'NSE_EQ', 'NFO', 'IDX_I')"
                  },
                  symbol: {
                    type: "string",
                    description: "Symbol to find (e.g., 'NIFTY', 'RELIANCE', 'NIFTY25JAN24500CE')"
                  }
                },
                required: %w[exchange_segment symbol]
              },
              outputs: {
                type: "object",
                properties: {
                  security_id: { type: "string" },
                  instrument_type: { type: "string" },
                  expiry_flag: { type: "boolean" },
                  bracket_flag: { type: "string" },
                  cover_flag: { type: "string" },
                  asm_gsm_flag: { type: "string" }
                }
              },
              side_effects: [],
              safety_rules: []
            },
            handler: lambda { |args|
              begin
                inst = DhanHQ::Models::Instrument.find(
                  args[:exchange_segment] || args["exchange_segment"],
                  args[:symbol] || args["symbol"]
                )
                inst ? inst.attributes : { error: "Instrument not found" }
              rescue StandardError => e
                { error: e.message }
              end
            }
          )

          # 2. LTP (Last Traded Price)
          registry.register(
            descriptor: {
              name: "dhan.market.ltp",
              category: "market",
              description: "Fetches latest traded price for an instrument",
              when_to_use: "When precise entry or stop-loss calculation is needed",
              when_not_to_use: "For fast exits (use WebSocket cache if available)",
              risk_level: :none,
              dependencies: {
                required_outputs: [
                  "instrument.security_id",
                  "instrument.exchange_segment"
                ]
              },
              inputs: {
                type: "object",
                properties: {
                  exchange_segment: { type: "string" },
                  security_id: { type: "string" }
                },
                required: %w[exchange_segment security_id]
              },
              outputs: {
                type: "object",
                properties: {
                  ltp: { type: "number" },
                  timestamp: { type: "string" }
                }
              },
              side_effects: [],
              safety_rules: []
            },
            handler: lambda { |args|
              begin
                # Try MarketFeed.ltp if available
                if defined?(DhanHQ::Models::MarketFeed) && DhanHQ::Models::MarketFeed.respond_to?(:ltp)
                  exchange_seg = args[:exchange_segment] || args["exchange_segment"]
                  sec_id = args[:security_id] || args["security_id"]

                  # API signature: MarketFeed.ltp("IDX_I" => [25])
                  # Returns: {"data"=>{"IDX_I"=>{"25"=>{"last_price"=>59011.35}}, "status"=>"success"}
                  # Build params like InstrumentHelpers.build_market_feed_params
                  params = { exchange_seg => [sec_id.to_i] }
                  result = DhanHQ::Models::MarketFeed.ltp(params)

                  # Extract last_price from nested response structure (matching InstrumentHelpers.ltp logic)
                  # Response format: {"data" => {"EXCHANGE_SEGMENT" => {"security_id" => {"last_price" => value}}}, "status" => "success"}
                  data = result[:data] || result["data"]

                  unless data
                    return { ltp: 0, timestamp: Time.now.iso8601,
                             error: "No data in response: #{result.inspect[0..200]}" }
                  end

                  # Try both symbol and string keys for exchange_segment
                  segment_data = data[exchange_seg] || data[exchange_seg.to_sym]

                  unless segment_data
                    return { ltp: 0, timestamp: Time.now.iso8601,
                             error: "No data for exchange_segment #{exchange_seg}: #{data.keys.inspect}" }
                  end

                  # Try both string and integer keys for security_id
                  security_data = segment_data[sec_id] || segment_data[sec_id.to_s] || segment_data[sec_id.to_i] || segment_data[sec_id.to_i.to_s]

                  unless security_data
                    return { ltp: 0, timestamp: Time.now.iso8601,
                             error: "No data for security_id #{sec_id}: #{segment_data.keys.inspect}" }
                  end

                  ltp_value = security_data[:last_price] || security_data["last_price"]

                  if ltp_value && ltp_value > 0
                    { ltp: ltp_value.to_f, timestamp: Time.now.iso8601 }
                  else
                    { ltp: 0, timestamp: Time.now.iso8601,
                      error: "last_price not found or invalid: #{security_data.inspect}" }
                  end
                else
                  { ltp: 0, timestamp: Time.now.iso8601, error: "LTP method not available" }
                end
              rescue StandardError => e
                { ltp: 0, timestamp: Time.now.iso8601, error: e.message }
              end
            }
          )

          # 3. Quote (Full market quote)
          registry.register(
            descriptor: {
              name: "dhan.market.quote",
              category: "market",
              description: "Fetches full market quote including bid/ask, volume, etc.",
              when_to_use: "When analyzing liquidity or spread before entry",
              when_not_to_use: "If only price is needed (use LTP)",
              risk_level: :none,
              dependencies: {
                required_outputs: [
                  "instrument.security_id",
                  "instrument.exchange_segment"
                ]
              },
              inputs: {
                type: "object",
                properties: {
                  exchange_segment: { type: "string" },
                  security_id: { type: "string" }
                },
                required: %w[exchange_segment security_id]
              },
              outputs: {
                type: "object",
                properties: {
                  ltp: { type: "number" },
                  bid: { type: "number" },
                  ask: { type: "number" },
                  volume: { type: "number" },
                  open_interest: { type: "number" }
                }
              },
              side_effects: [],
              safety_rules: []
            },
            handler: lambda { |args|
              begin
                if defined?(DhanHQ::Models::MarketFeed) && DhanHQ::Models::MarketFeed.respond_to?(:quote)
                  DhanHQ::Models::MarketFeed.quote(
                    exchange_segment: args[:exchange_segment] || args["exchange_segment"],
                    security_id: args[:security_id] || args["security_id"]
                  )
                else
                  { error: "Quote method not available" }
                end
              rescue StandardError => e
                { error: e.message }
              end
            }
          )

          # 4. OHLC (Open, High, Low, Close)
          registry.register(
            descriptor: {
              name: "dhan.market.ohlc",
              category: "market",
              description: "Fetches OHLC data for current day",
              when_to_use: "When analyzing intraday price action",
              when_not_to_use: "For historical analysis (use history.intraday)",
              risk_level: :none,
              dependencies: {
                required_outputs: [
                  "instrument.security_id",
                  "instrument.exchange_segment"
                ]
              },
              inputs: {
                type: "object",
                properties: {
                  exchange_segment: { type: "string" },
                  security_id: { type: "string" }
                },
                required: %w[exchange_segment security_id]
              },
              outputs: {
                type: "object",
                properties: {
                  open: { type: "number" },
                  high: { type: "number" },
                  low: { type: "number" },
                  close: { type: "number" }
                }
              },
              side_effects: [],
              safety_rules: []
            },
            handler: lambda { |args|
              begin
                if defined?(DhanHQ::Models::MarketFeed) && DhanHQ::Models::MarketFeed.respond_to?(:ohlc)
                  DhanHQ::Models::MarketFeed.ohlc(
                    exchange_segment: args[:exchange_segment] || args["exchange_segment"],
                    security_id: args[:security_id] || args["security_id"]
                  )
                else
                  { error: "OHLC method not available" }
                end
              rescue StandardError => e
                { error: e.message }
              end
            }
          )
        end

        # ============================================
        # HISTORICAL & RESEARCH TOOLS (READ-ONLY)
        # ============================================

        def self.register_historical_tools(registry, dhan_client)
          # 5. Intraday OHLC (Production-Grade with Trading Day Validation)
          registry.register(
            descriptor: {
              name: "dhan.history.intraday",
              category: "market.history",
              description: "Fetch intraday OHLC candles for a given timeframe",
              purpose: "Multi-timeframe analysis, regime detection, and setup validation",
              when_to_use: [
                "Multi-timeframe analysis in Agent A",
                "Structure and momentum analysis",
                "Regime detection and setup validation"
              ],
              when_not_to_use: [
                "After analysis complete",
                "Repeatedly for same timeframe in same iteration",
                "For live trailing or exits (use market data)",
                "During ORDER_EXECUTION or POSITION_TRACKING phases"
              ],
              risk_level: :none,
              dependencies: {
                required_tools: ["dhan.instrument.find"],
                required_outputs: [
                  "instrument.security_id",
                  "instrument.exchange_segment",
                  "instrument.instrument_type",
                  "analysis_context.interval",
                  "analysis_context.from_date",
                  "analysis_context.to_date",
                  "analysis_context.date_mode"
                ],
                forbidden_states: ["ORDER_EXECUTION", "POSITION_TRACKING"],
                derived_inputs: {
                  "security_id" => "instrument.security_id",
                  "exchange_segment" => "instrument.exchange_segment",
                  "instrument" => "instrument.instrument_type",
                  "interval" => "analysis_context.interval",
                  "from_date" => "analysis_context.from_date",
                  "to_date" => "analysis_context.to_date"
                },
                date_constraints: {
                  "LIVE" => {
                    "to_date" => "TODAY",
                    "from_date" => "LAST_TRADING_DAY_BEFORE"
                  },
                  "HISTORICAL" => {
                    "from_date" => "<= to_date",
                    "must_be_trading_days" => true
                  }
                },
                produces: ["intraday_candles"]
              },
              inputs: {
                type: "object",
                properties: {
                  security_id: {
                    type: "string",
                    description: "Resolved security id from dhan.instrument.find"
                  },
                  exchange_segment: {
                    type: "string",
                    description: "Exchange segment of the instrument"
                  },
                  instrument: {
                    type: "string",
                    enum: %w[INDEX EQUITY FUT OPT],
                    description: "Instrument type as required by Dhan API"
                  },
                  interval: {
                    type: "string",
                    enum: %w[1 5 15 25 60],
                    description: "Candle interval in minutes"
                  },
                  from_date: {
                    type: "string",
                    format: "date",
                    description: "Start date (must be < to_date in LIVE mode)"
                  },
                  to_date: {
                    type: "string",
                    format: "date",
                    description: "End date (must be today in LIVE mode)"
                  }
                },
                required: %w[security_id exchange_segment instrument interval from_date to_date]
              },
              outputs: {
                type: "object",
                properties: {
                  candles: {
                    type: "array",
                    items: {
                      type: "object",
                      properties: {
                        ts: { type: "integer", description: "Epoch timestamp" },
                        open: { type: "number" },
                        high: { type: "number" },
                        low: { type: "number" },
                        close: { type: "number" },
                        volume: { type: "integer", description: "Volume traded in the timeframe" },
                        open_interest: { type: "integer", description: "Open Interest (for F&O instruments, optional)" }
                      },
                      required: %w[ts open high low close]
                    }
                  },
                  interval: {
                    type: "string",
                    description: "Interval of returned candles"
                  },
                  complete: {
                    type: "boolean",
                    description: "True if the last candle is CLOSED and safe to use"
                  }
                },
                required: %w[candles interval complete]
              },
              side_effects: [],
              safety_rules: [
                "Never use last candle if complete=false",
                "LIVE mode requires previous-session context",
                "from_date must be a trading day (never weekend or holiday)",
                "Controller resolves last trading day automatically",
                "Interval must match analysis_context interval",
                "Do not mix multiple intervals in the same reasoning step",
                "Do not call repeatedly in the same iteration"
              ],
              examples: {
                valid: [
                  {
                    input: {
                      security_id: "13",
                      exchange_segment: "IDX_I",
                      instrument: "INDEX",
                      interval: "5",
                      from_date: "2025-01-17",
                      to_date: "2025-01-20"
                    },
                    comment: "LIVE intraday NIFTY analysis on Monday with last trading day (Friday) - correct Monday handling"
                  },
                  {
                    input: {
                      security_id: "13",
                      exchange_segment: "IDX_I",
                      instrument: "INDEX",
                      interval: "15",
                      from_date: "2024-12-01",
                      to_date: "2024-12-31"
                    },
                    comment: "HISTORICAL intraday data for backtesting"
                  }
                ],
                invalid: [
                  {
                    input: {
                      security_id: "13",
                      exchange_segment: "IDX_I",
                      instrument: "INDEX",
                      interval: "5",
                      from_date: "2025-01-20",
                      to_date: "2025-01-20"
                    },
                    reason: "LIVE mode cannot use same-day from_date and to_date"
                  },
                  {
                    input: {
                      security_id: "13",
                      exchange_segment: "IDX_I",
                      instrument: "INDEX",
                      interval: "5"
                    },
                    reason: "Missing exchange_segment, instrument, and date range"
                  },
                  {
                    input: {
                      interval: "2"
                    },
                    reason: "Interval not supported by Dhan"
                  }
                ]
              }
            },
            handler: lambda { |args|
              begin
                security_id = args[:security_id] || args["security_id"]
                exchange_segment = args[:exchange_segment] || args["exchange_segment"]
                instrument = args[:instrument] || args["instrument"]
                interval = args[:interval] || args["interval"]
                from_date = args[:from_date] || args["from_date"]
                to_date = args[:to_date] || args["to_date"]

                # Validate interval
                unless %w[1 5 15 25 60].include?(interval)
                  return {
                    error: "Invalid interval: #{interval}. Must be one of: 1, 5, 15, 25, 60",
                    candles: [],
                    interval: interval,
                    complete: false
                  }
                end

                # Validate and parse dates
                from_dt = Date.parse(from_date)
                to_dt = Date.parse(to_date)

                # Check if dates are valid trading days (using TradingCalendar)
                trading_validation_from = Vyapari::TradingCalendar.validate_trading_day(from_dt)
                unless trading_validation_from[:valid]
                  return {
                    error: "from_date (#{from_date}) #{trading_validation_from[:error]}",
                    candles: [],
                    interval: interval,
                    complete: false
                  }
                end

                # Note: to_date doesn't need to be a trading day (it's just the end of the range)
                # Only from_date must be a trading day to ensure we get actual trading data

                # Check LIVE mode constraint: from_date must be before to_date
                if from_dt >= to_dt
                  return {
                    error: "LIVE mode constraint: from_date (#{from_date}) must be before to_date (#{to_date})",
                    candles: [],
                    interval: interval,
                    complete: false
                  }
                end

                # Fetch data from DhanHQ
                raw_data = DhanHQ::Models::HistoricalData.intraday(
                  security_id: security_id,
                  exchange_segment: exchange_segment,
                  instrument: instrument,
                  interval: interval,
                  from_date: from_date,
                  to_date: to_date
                )

                # Transform to production-grade format with complete flag
                result = transform_to_candles_with_complete(raw_data, interval)
                result[:interval] = interval
                result
              rescue Date::Error => e
                {
                  error: "Invalid date format: #{e.message}",
                  candles: [],
                  interval: interval || "unknown",
                  complete: false
                }
              rescue StandardError => e
                {
                  error: e.message,
                  candles: [],
                  interval: interval || "unknown",
                  complete: false
                }
              end
            }
          )

          # 6. Daily OHLC
          registry.register(
            descriptor: {
              name: "dhan.history.daily",
              category: "historical",
              description: "Fetches daily OHLC bars for swing trading analysis",
              when_to_use: "For swing trading or longer-term analysis",
              when_not_to_use: "For intraday trading",
              risk_level: :none,
              dependencies: {
                required_outputs: [
                  "instrument.security_id",
                  "instrument.exchange_segment",
                  "instrument.instrument_type"
                ]
              },
              inputs: {
                type: "object",
                properties: {
                  security_id: { type: "string" },
                  exchange_segment: { type: "string" },
                  instrument: { type: "string" },
                  from_date: { type: "string" },
                  to_date: { type: "string" }
                },
                required: %w[security_id exchange_segment instrument from_date to_date]
              },
              outputs: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    open: { type: "number" },
                    high: { type: "number" },
                    low: { type: "number" },
                    close: { type: "number" },
                    volume: { type: "number" },
                    date: { type: "string" }
                  }
                }
              },
              side_effects: [],
              safety_rules: []
            },
            handler: lambda { |args|
              begin
                if DhanHQ::Models::HistoricalData.respond_to?(:daily)
                  raw_data = DhanHQ::Models::HistoricalData.daily(
                    security_id: args[:security_id] || args["security_id"],
                    exchange_segment: args[:exchange_segment] || args["exchange_segment"],
                    instrument: args[:instrument] || args["instrument"],
                    from_date: args[:from_date] || args["from_date"],
                    to_date: args[:to_date] || args["to_date"]
                  )
                  transform_to_candles(raw_data)
                else
                  { error: "Daily data method not available", candles: [] }
                end
              rescue StandardError => e
                { error: e.message, candles: [] }
              end
            }
          )

          # 7. Option Chain
          registry.register(
            descriptor: {
              name: "dhan.option.chain",
              category: "options",
              description: "Fetches option chain for an expiry with strikes, premiums, Greeks",
              when_to_use: "Strike selection and IV analysis before entry",
              when_not_to_use: "After entry execution",
              risk_level: :none,
              dependencies: {
                required_tools: [
                  "dhan.instrument.find",
                  "dhan.option.expiries"
                ],
                required_outputs: [
                  "instrument.security_id",
                  "instrument.exchange_segment",
                  "expiry_list"
                ],
                derived_inputs: {
                  "underlying_scrip" => "instrument.security_id",
                  "underlying_seg" => "instrument.exchange_segment",
                  "expiry" => "expiry_list[0]"
                }
              },
              inputs: {
                type: "object",
                properties: {
                  underlying_scrip: {
                    type: "integer",
                    description: "Underlying security_id (integer, e.g., 13 for NIFTY). Automatically derived from instrument.find if not provided."
                  },
                  underlying_seg: {
                    type: "string",
                    description: "Underlying segment (e.g., 'IDX_I' for indices). Automatically derived from instrument.find if not provided."
                  },
                  expiry: {
                    type: "string",
                    description: "Expiry date (YYYY-MM-DD format). Automatically derived from expiry_list[0] (nearest expiry) if not provided."
                  }
                },
                required: %w[underlying_scrip underlying_seg]
              },
              outputs: {
                type: "object",
                properties: {
                  contracts: {
                    type: "array",
                    description: "Array of option contracts"
                  },
                  spot_price: { type: "number" }
                }
              },
              side_effects: [],
              safety_rules: [
                "Only nearest expiry allowed for intraday",
                "Do not refetch chain repeatedly in same iteration"
              ]
            },
            handler: lambda { |args|
              begin
                if defined?(DhanHQ::Models::OptionChain) && DhanHQ::Models::OptionChain.respond_to?(:fetch)
                  # Convert underlying_scrip to integer (API requires integer, not string)
                  underlying_scrip = args[:underlying_scrip] || args["underlying_scrip"]
                  underlying_scrip = underlying_scrip.to_i if underlying_scrip.respond_to?(:to_i)

                  # Validate expiry is provided
                  expiry = args[:expiry] || args["expiry"]
                  unless expiry && !expiry.to_s.empty?
                    return {
                      error: "Expiry is required. The tool query handler should have resolved this automatically. Please check expiry resolution logic.", contracts: [], spot_price: 0
                    }
                  end

                  result = DhanHQ::Models::OptionChain.fetch(
                    underlying_scrip: underlying_scrip,
                    underlying_seg: args[:underlying_seg] || args["underlying_seg"],
                    expiry: args[:expiry] || args["expiry"]
                  )

                  # Transform response to match expected format
                  # API returns: { :last_price => Float, :oc => { "strike" => { "ce" => {...}, "pe" => {...} } } }
                  # Expected: { contracts: [...], spot_price: Float }
                  if result.is_a?(Hash) && result[:oc]
                    contracts = []
                    spot_price = result[:last_price] || result["last_price"] || 0

                    result[:oc].each do |strike_str, strike_data|
                      strike = strike_str.to_f

                      # Add CE contract if present and tradable
                      if strike_data["ce"] || strike_data[:ce]
                        ce = strike_data["ce"] || strike_data[:ce]
                        ce_ltp = ce[:last_price] || ce["last_price"] || 0
                        ce_bid = ce[:top_bid_price] || ce["top_bid_price"] || 0
                        ce_ask = ce[:top_ask_price] || ce["top_ask_price"] || 0
                        ce_oi = ce[:oi] || ce["oi"] || 0

                        # Filter: Only include contracts with liquidity (LTP > 0 OR bid/ask > 0) AND reasonable OI
                        if (ce_ltp > 0 || ce_bid > 0 || ce_ask > 0) && ce_oi > 0
                          contracts << {
                            security_id: ce[:security_id] || ce["security_id"],
                            strike: strike,
                            type: "CE",
                            ltp: ce_ltp,
                            bid: ce_bid,
                            ask: ce_ask,
                            open_interest: ce_oi,
                            delta: ce.dig(:greeks, :delta) || ce.dig("greeks", "delta") || 0,
                            gamma: ce.dig(:greeks, :gamma) || ce.dig("greeks", "gamma") || 0,
                            theta: ce.dig(:greeks, :theta) || ce.dig("greeks", "theta") || 0,
                            vega: ce.dig(:greeks, :vega) || ce.dig("greeks", "vega") || 0,
                            volume: ce[:volume] || ce["volume"] || 0,
                            implied_volatility: ce[:implied_volatility] || ce["implied_volatility"] || 0
                          }
                        end
                      end

                      # Add PE contract if present and tradable
                      next unless strike_data["pe"] || strike_data[:pe]

                      pe = strike_data["pe"] || strike_data[:pe]
                      pe_ltp = pe[:last_price] || pe["last_price"] || 0
                      pe_bid = pe[:top_bid_price] || pe["top_bid_price"] || 0
                      pe_ask = pe[:top_ask_price] || pe["top_ask_price"] || 0
                      pe_oi = pe[:oi] || pe["oi"] || 0

                      # Filter: Only include contracts with liquidity (LTP > 0 OR bid/ask > 0) AND reasonable OI
                      next unless (pe_ltp > 0 || pe_bid > 0 || pe_ask > 0) && pe_oi > 0

                      contracts << {
                        security_id: pe[:security_id] || pe["security_id"],
                        strike: strike,
                        type: "PE",
                        ltp: pe_ltp,
                        bid: pe_bid,
                        ask: pe_ask,
                        open_interest: pe_oi,
                        delta: pe.dig(:greeks, :delta) || pe.dig("greeks", "delta") || 0,
                        gamma: pe.dig(:greeks, :gamma) || pe.dig("greeks", "gamma") || 0,
                        theta: pe.dig(:greeks, :theta) || pe.dig("greeks", "theta") || 0,
                        vega: pe.dig(:greeks, :vega) || pe.dig("greeks", "vega") || 0,
                        volume: pe[:volume] || pe["volume"] || 0,
                        implied_volatility: pe[:implied_volatility] || pe["implied_volatility"] || 0
                      }
                    end

                    # Filter and rank for option buying
                    if spot_price > 0
                      # Calculate quality score for each contract (higher = better for buying)
                      contracts.each do |contract|
                        strike = contract[:strike]
                        ltp = contract[:ltp] || 0
                        bid = contract[:bid] || 0
                        ask = contract[:ask] || 0
                        oi = contract[:open_interest] || 0
                        volume = contract[:volume] || 0

                        # Calculate metrics
                        spread = ask > 0 && bid > 0 ? (ask - bid) / ask : Float::INFINITY
                        spread_pct = ltp > 0 ? spread * 100 : Float::INFINITY
                        distance_from_atm = (strike - spot_price).abs
                        distance_pct = (distance_from_atm / spot_price) * 100

                        # Quality score for option buying (higher = better)
                        # Factors: Near ATM, High OI, High Volume, Low Spread, Has LTP
                        quality_score = 0
                        quality_score += 100 - distance_pct if distance_pct <= 20 # Prefer ATM (±20%)
                        quality_score += [oi / 1000.0, 50].min # OI bonus (capped at 50)
                        quality_score += [volume / 100.0, 30].min # Volume bonus (capped at 30)
                        quality_score += 20 if ltp > 0 # Has LTP
                        quality_score -= spread_pct * 2 if spread_pct < 5 # Penalize wide spreads
                        quality_score += 10 if spread_pct < 1 # Bonus for tight spreads

                        contract[:quality_score] = quality_score
                        contract[:distance_from_atm] = distance_from_atm
                        contract[:distance_pct] = distance_pct
                        contract[:spread_pct] = spread_pct
                      end

                      # Sort by quality score (descending) - best contracts first
                      contracts.sort_by! { |c| -c[:quality_score] }

                      # Take top contracts: ATM focus (±10% of spot) with best quality
                      atm_range = (spot_price * 0.9)..(spot_price * 1.1)
                      atm_contracts = contracts.select { |c| atm_range.include?(c[:strike]) }

                      contracts = if atm_contracts.any?
                                    # Take top 20 ATM contracts
                                    atm_contracts.first(20)
                                  else
                                    # If no ATM contracts, take top 30 by quality
                                    contracts.first(30)
                                  end
                    else
                      # No spot price - sort by OI + Volume, take top 30
                      contracts.sort_by! { |c| -((c[:open_interest] || 0) + (c[:volume] || 0)) }
                      contracts = contracts.first(30)
                    end

                    { contracts: contracts, spot_price: spot_price, total_filtered: contracts.length }
                  elsif result.is_a?(Hash) && result["oc"]
                    # Handle string keys - apply same filtering logic
                    contracts = []
                    spot_price = result[:last_price] || result["last_price"] || 0

                    result["oc"].each do |strike_str, strike_data|
                      strike = strike_str.to_f

                      # Add CE contract if tradable
                      if strike_data["ce"] || strike_data[:ce]
                        ce = strike_data["ce"] || strike_data[:ce]
                        ce_ltp = ce[:last_price] || ce["last_price"] || 0
                        ce_bid = ce[:top_bid_price] || ce["top_bid_price"] || 0
                        ce_ask = ce[:top_ask_price] || ce["top_ask_price"] || 0
                        ce_oi = ce[:oi] || ce["oi"] || 0

                        if (ce_ltp > 0 || ce_bid > 0 || ce_ask > 0) && ce_oi > 0
                          contracts << {
                            security_id: ce[:security_id] || ce["security_id"],
                            strike: strike,
                            type: "CE",
                            ltp: ce_ltp,
                            bid: ce_bid,
                            ask: ce_ask,
                            open_interest: ce_oi,
                            delta: ce.dig(:greeks, :delta) || ce.dig("greeks", "delta") || 0,
                            gamma: ce.dig(:greeks, :gamma) || ce.dig("greeks", "gamma") || 0,
                            theta: ce.dig(:greeks, :theta) || ce.dig("greeks", "theta") || 0,
                            vega: ce.dig(:greeks, :vega) || ce.dig("greeks", "vega") || 0,
                            volume: ce[:volume] || ce["volume"] || 0,
                            implied_volatility: ce[:implied_volatility] || ce["implied_volatility"] || 0
                          }
                        end
                      end

                      # Add PE contract if tradable
                      next unless strike_data["pe"] || strike_data[:pe]

                      pe = strike_data["pe"] || strike_data[:pe]
                      pe_ltp = pe[:last_price] || pe["last_price"] || 0
                      pe_bid = pe[:top_bid_price] || pe["top_bid_price"] || 0
                      pe_ask = pe[:top_ask_price] || pe["top_ask_price"] || 0
                      pe_oi = pe[:oi] || pe["oi"] || 0

                      next unless (pe_ltp > 0 || pe_bid > 0 || pe_ask > 0) && pe_oi > 0

                      contracts << {
                        security_id: pe[:security_id] || pe["security_id"],
                        strike: strike,
                        type: "PE",
                        ltp: pe_ltp,
                        bid: pe_bid,
                        ask: pe_ask,
                        open_interest: pe_oi,
                        delta: pe.dig(:greeks, :delta) || pe.dig("greeks", "delta") || 0,
                        gamma: pe.dig(:greeks, :gamma) || pe.dig("greeks", "gamma") || 0,
                        theta: pe.dig(:greeks, :theta) || pe.dig("greeks", "theta") || 0,
                        vega: pe.dig(:greeks, :vega) || pe.dig("greeks", "vega") || 0,
                        volume: pe[:volume] || pe["volume"] || 0,
                        implied_volatility: pe[:implied_volatility] || pe["implied_volatility"] || 0
                      }
                    end

                    # Filter and rank for option buying (same logic as above)
                    if spot_price > 0
                      # Calculate quality score for each contract
                      contracts.each do |contract|
                        strike = contract[:strike]
                        ltp = contract[:ltp] || 0
                        bid = contract[:bid] || 0
                        ask = contract[:ask] || 0
                        oi = contract[:open_interest] || 0
                        volume = contract[:volume] || 0

                        spread = ask > 0 && bid > 0 ? (ask - bid) / ask : Float::INFINITY
                        spread_pct = ltp > 0 ? spread * 100 : Float::INFINITY
                        distance_from_atm = (strike - spot_price).abs
                        distance_pct = (distance_from_atm / spot_price) * 100

                        quality_score = 0
                        quality_score += 100 - distance_pct if distance_pct <= 20
                        quality_score += [oi / 1000.0, 50].min
                        quality_score += [volume / 100.0, 30].min
                        quality_score += 20 if ltp > 0
                        quality_score -= spread_pct * 2 if spread_pct < 5
                        quality_score += 10 if spread_pct < 1

                        contract[:quality_score] = quality_score
                        contract[:distance_from_atm] = distance_from_atm
                        contract[:distance_pct] = distance_pct
                        contract[:spread_pct] = spread_pct
                      end

                      contracts.sort_by! { |c| -c[:quality_score] }

                      atm_range = (spot_price * 0.9)..(spot_price * 1.1)
                      atm_contracts = contracts.select { |c| atm_range.include?(c[:strike]) }

                      contracts = if atm_contracts.any?
                                    atm_contracts.first(20)
                                  else
                                    contracts.first(30)
                                  end
                    else
                      contracts.sort_by! { |c| -((c[:open_interest] || 0) + (c[:volume] || 0)) }
                      contracts = contracts.first(30)
                    end

                    { contracts: contracts, spot_price: spot_price, total_filtered: contracts.length }
                  else
                    # Return as-is if already in expected format or error
                    result
                  end
                else
                  { error: "OptionChain.fetch not available", contracts: [], spot_price: 0 }
                end
              rescue StandardError => e
                { error: e.message, contracts: [], spot_price: 0 }
              end
            }
          )

          # 8. Option Expiries
          registry.register(
            descriptor: {
              name: "dhan.option.expiries",
              category: "options",
              description: "Fetches available expiry dates for an underlying",
              when_to_use: "Before fetching option chain to select expiry",
              when_not_to_use: "If expiry already known",
              risk_level: :none,
              dependencies: {
                required_tools: [
                  "dhan.instrument.find"
                ],
                required_outputs: [
                  "instrument.security_id",
                  "instrument.exchange_segment"
                ],
                derived_inputs: {
                  "underlying_scrip" => "instrument.security_id",
                  "underlying_seg" => "instrument.exchange_segment"
                },
                produces: ["expiry_list"]
              },
              inputs: {
                type: "object",
                properties: {
                  underlying_scrip: {
                    type: "integer",
                    description: "Underlying security_id (integer, e.g., 13 for NIFTY). Must be an integer."
                  },
                  underlying_seg: {
                    type: "string",
                    description: "Underlying segment (e.g., 'IDX_I' for indices)"
                  },
                  expiry: {
                    type: "string",
                    description: "Any valid expiry date (YYYY-MM-DD format). Required by API but can be any date - used only to fetch the expiry list."
                  }
                },
                required: %w[underlying_scrip underlying_seg]
              },
              outputs: {
                type: "array",
                items: {
                  type: "string",
                  description: "Expiry date (YYYY-MM-DD)"
                }
              },
              side_effects: [],
              safety_rules: []
            },
            handler: lambda { |args|
              begin
                if defined?(DhanHQ::Models::OptionChain) && DhanHQ::Models::OptionChain.respond_to?(:fetch_expiry_list)
                  # Convert underlying_scrip to integer if needed
                  underlying_scrip = args[:underlying_scrip] || args["underlying_scrip"]
                  underlying_scrip = underlying_scrip.to_i if underlying_scrip.respond_to?(:to_i)

                  # fetch_expiry_list requires expiry parameter (can use any valid expiry)
                  # We'll use today's date or a default expiry
                  expiry = args[:expiry] || args["expiry"] || Date.today.strftime("%Y-%m-%d")

                  result = DhanHQ::Models::OptionChain.fetch_expiry_list(
                    underlying_scrip: underlying_scrip,
                    underlying_seg: args[:underlying_seg] || args["underlying_seg"],
                    expiry: expiry
                  )

                  # Return as array format expected by tool
                  if result.is_a?(Array)
                    result
                  elsif result.is_a?(Hash) && (result[:expiries] || result["expiries"])
                    result[:expiries] || result["expiries"]
                  elsif result.is_a?(Hash) && result[:data] && result[:data].is_a?(Array)
                    result[:data]
                  elsif result.is_a?(Hash) && result["data"] && result["data"].is_a?(Array)
                    result["data"]
                  else
                    []
                  end
                else
                  { error: "fetch_expiry_list method not available", expiries: [] }
                end
              rescue StandardError => e
                { error: e.message, expiries: [] }
              end
            }
          )
        end

        # ============================================
        # ACCOUNT STATE TOOLS (READ-ONLY)
        # ============================================

        def self.register_account_tools(registry, dhan_client)
          # 9. Funds Balance
          registry.register(
            descriptor: {
              name: "dhan.funds.balance",
              category: "account",
              description: "Fetches available margin and balance",
              when_to_use: "Before placing any order to check available funds",
              when_not_to_use: "Inside WebSocket tick handler",
              risk_level: :none,
              inputs: {
                type: "object",
                properties: {},
                required: []
              },
              outputs: {
                type: "object",
                properties: {
                  available_balance: { type: "number" },
                  used_margin: { type: "number" },
                  total_balance: { type: "number" }
                }
              },
              side_effects: [],
              safety_rules: []
            },
            handler: lambda { |_args|
              begin
                if defined?(DhanHQ::Models::Funds) && DhanHQ::Models::Funds.respond_to?(:balance)
                  DhanHQ::Models::Funds.balance
                else
                  { error: "Funds balance not available", available_balance: 0 }
                end
              rescue StandardError => e
                { error: e.message, available_balance: 0 }
              end
            }
          )

          # 10. Positions List
          registry.register(
            descriptor: {
              name: "dhan.positions.list",
              category: "account",
              description: "Fetches current open positions",
              when_to_use: "When checking current exposure, calculating risk, or before placing new orders",
              when_not_to_use: "If position data is already cached and recent",
              risk_level: :none,
              dependencies: {
                required_tools: [],
                produces: ["open_positions"]
              },
              inputs: {
                type: "object",
                properties: {},
                required: []
              },
              outputs: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    security_id: { type: "string" },
                    quantity: { type: "integer" },
                    average_price: { type: "number" },
                    ltp: { type: "number" },
                    pnl: { type: "number" }
                  }
                }
              },
              side_effects: [],
              safety_rules: []
            },
            handler: lambda { |_args|
              begin
                if defined?(DhanHQ::Models::Position)
                  # Try .all first (most common), then .list, then fallback
                  positions = if DhanHQ::Models::Position.respond_to?(:all)
                                DhanHQ::Models::Position.all
                              elsif DhanHQ::Models::Position.respond_to?(:list)
                                DhanHQ::Models::Position.list
                              else
                                []
                              end

                  # Convert Position objects to hash format expected by tool
                  if positions.is_a?(Array) && !positions.empty? && positions.first.respond_to?(:attributes)
                    positions.map do |pos|
                      {
                        security_id: pos.security_id.to_s,
                        trading_symbol: pos.trading_symbol,
                        position_type: pos.position_type,
                        exchange_segment: pos.exchange_segment,
                        product_type: pos.product_type,
                        quantity: pos.net_qty || pos.buy_qty || 0,
                        average_price: pos.buy_avg || pos.cost_price || 0.0,
                        current_price: pos.cost_price || 0.0,
                        pnl: pos.unrealized_profit || 0.0,
                        realized_pnl: pos.realized_profit || 0.0,
                        multiplier: pos.multiplier || 1
                      }
                    end
                  elsif positions.is_a?(Array)
                    # Already in array format
                    positions
                  else
                    []
                  end
                else
                  { error: "Positions list not available", positions: [] }
                end
              rescue StandardError => e
                { error: e.message, positions: [] }
              end
            }
          )

          # 11. Holdings List
          registry.register(
            descriptor: {
              name: "dhan.holdings.list",
              category: "account",
              description: "Fetches equity holdings (for swing trading)",
              when_to_use: "When checking equity portfolio",
              when_not_to_use: "For options/futures trading",
              risk_level: :none,
              inputs: {
                type: "object",
                properties: {},
                required: []
              },
              outputs: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    security_id: { type: "string" },
                    quantity: { type: "integer" },
                    average_price: { type: "number" }
                  }
                }
              },
              side_effects: [],
              safety_rules: []
            },
            handler: lambda { |_args|
              begin
                if defined?(DhanHQ::Models::Holding) && DhanHQ::Models::Holding.respond_to?(:list)
                  DhanHQ::Models::Holding.list
                else
                  { error: "Holdings list not available", holdings: [] }
                end
              rescue StandardError => e
                { error: e.message, holdings: [] }
              end
            }
          )

          # 12. Orders List
          registry.register(
            descriptor: {
              name: "dhan.orders.list",
              category: "account",
              description: "Fetches order status and history",
              when_to_use: "When checking order execution status",
              when_not_to_use: "For real-time fills (use WebSocket)",
              risk_level: :none,
              dependencies: {
                required_tools: []
              },
              inputs: {
                type: "object",
                properties: {},
                required: []
              },
              outputs: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    order_id: { type: "string" },
                    status: { type: "string" },
                    quantity: { type: "integer" },
                    filled_quantity: { type: "integer" }
                  }
                }
              },
              side_effects: [],
              safety_rules: []
            },
            handler: lambda { |_args|
              begin
                if defined?(DhanHQ::Models::Order) && DhanHQ::Models::Order.respond_to?(:list)
                  DhanHQ::Models::Order.list
                else
                  { error: "Orders list not available", orders: [] }
                end
              rescue StandardError => e
                { error: e.message, orders: [] }
              end
            }
          )

          # 13. Today's Trades
          registry.register(
            descriptor: {
              name: "dhan.trades.today",
              category: "account",
              description: "Fetches today's executed trades",
              when_to_use: "When analyzing today's performance",
              when_not_to_use: "For real-time execution (use WebSocket)",
              risk_level: :none,
              inputs: {
                type: "object",
                properties: {},
                required: []
              },
              outputs: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    trade_id: { type: "string" },
                    security_id: { type: "string" },
                    quantity: { type: "integer" },
                    price: { type: "number" },
                    pnl: { type: "number" }
                  }
                }
              },
              side_effects: [],
              safety_rules: []
            },
            handler: lambda { |_args|
              begin
                if defined?(DhanHQ::Models::Trade) && DhanHQ::Models::Trade.respond_to?(:today)
                  DhanHQ::Models::Trade.today
                else
                  { error: "Trades today not available", trades: [] }
                end
              rescue StandardError => e
                { error: e.message, trades: [] }
              end
            }
          )
        end

        # ============================================
        # TRADING ACTION TOOLS (WRITE - GUARDED)
        # ============================================

        def self.register_trading_tools(registry, dhan_client)
          # 14. Place Order
          registry.register(
            descriptor: {
              name: "dhan.order.place",
              category: "trade",
              description: "Places a standard order on DhanHQ",
              when_to_use: "Only after risk validation and stop-loss planned",
              when_not_to_use: "Without SL/TP planned or during uncertainty",
              risk_level: :high,
              side_effects: ["REAL MONEY ORDER"],
              dependencies: {
                required_states: ["ORDER_EXECUTION"],
                required_outputs: [
                  "validated_trade_plan",
                  "final_quantity",
                  "numeric_stop_loss"
                ],
                required_guards: [
                  "RiskGuard",
                  "ExecutionGuard"
                ],
                forbidden_after: [
                  "position_opened",
                  "order_failed"
                ],
                max_calls_per_trade: 1
              },
              inputs: {
                type: "object",
                properties: {
                  transaction_type: {
                    type: "string",
                    enum: %w[BUY SELL]
                  },
                  exchange_segment: { type: "string" },
                  product_type: { type: "string" },
                  order_type: {
                    type: "string",
                    enum: %w[MARKET LIMIT]
                  },
                  security_id: { type: "string" },
                  quantity: {
                    type: "integer",
                    minimum: 1
                  },
                  price: {
                    type: "number",
                    nullable: true,
                    description: "Required for LIMIT orders"
                  }
                },
                required: %w[transaction_type exchange_segment product_type order_type security_id quantity]
              },
              outputs: {
                type: "object",
                properties: {
                  order_id: { type: "string" },
                  status: { type: "string" }
                }
              },
              safety_rules: [
                "Never place order without stoploss planned",
                "Never exceed max position size",
                "Never place order during market closure"
              ]
            },
            handler: lambda { |args|
              if ENV["DRY_RUN"] == "true" || ENV["DRY_RUN_MODE"] == "true"
                {
                  order_id: "SIMULATED_#{Time.now.to_i}",
                  status: "DRY_RUN",
                  message: "Order simulated - dry-run mode active"
                }
              else
                begin
                  order = DhanHQ::Models::Order.new(
                    transaction_type: args[:transaction_type] || args["transaction_type"],
                    exchange_segment: args[:exchange_segment] || args["exchange_segment"],
                    product_type: args[:product_type] || args["product_type"],
                    order_type: args[:order_type] || args["order_type"],
                    security_id: args[:security_id] || args["security_id"],
                    quantity: args[:quantity] || args["quantity"],
                    price: args[:price] || args["price"]
                  )
                  order.save
                  { order_id: order.order_id, status: order.status }
                rescue StandardError => e
                  { order_id: nil, status: "error", error: e.message }
                end
              end
            }
          )

          # 15. Modify Order
          registry.register(
            descriptor: {
              name: "dhan.order.modify",
              category: "trade",
              description: "Modifies an existing order (price, quantity)",
              when_to_use: "When adjusting limit price or quantity",
              when_not_to_use: "If order already executed",
              risk_level: :high,
              side_effects: ["MODIFIES REAL ORDER"],
              dependencies: {
                required_outputs: [
                  "order_id"
                ],
                max_calls_per_trade: 1
              },
              inputs: {
                type: "object",
                properties: {
                  order_id: { type: "string" },
                  price: { type: "number" },
                  quantity: { type: "integer" }
                },
                required: ["order_id"]
              },
              outputs: {
                type: "object",
                properties: {
                  order_id: { type: "string" },
                  status: { type: "string" }
                }
              },
              safety_rules: [
                "Never modify executed orders",
                "Verify order status before modification"
              ]
            },
            handler: lambda { |args|
              if ENV["DRY_RUN"] == "true" || ENV["DRY_RUN_MODE"] == "true"
                {
                  order_id: args[:order_id] || args["order_id"],
                  status: "DRY_RUN_MODIFIED",
                  message: "Order modification simulated"
                }
              else
                begin
                  order = DhanHQ::Models::Order.find(args[:order_id] || args["order_id"])
                  order.price = args[:price] || args["price"] if args[:price] || args["price"]
                  order.quantity = args[:quantity] || args["quantity"] if args[:quantity] || args["quantity"]
                  order.save
                  { order_id: order.order_id, status: order.status }
                rescue StandardError => e
                  { order_id: nil, status: "error", error: e.message }
                end
              end
            }
          )

          # 16. Cancel Order
          registry.register(
            descriptor: {
              name: "dhan.order.cancel",
              category: "trade",
              description: "Cancels an existing order",
              when_to_use: "When order is no longer needed",
              when_not_to_use: "If order already executed",
              risk_level: :high,
              side_effects: ["CANCELS REAL ORDER"],
              dependencies: {
                required_outputs: [
                  "order_id"
                ],
                max_calls_per_trade: 1
              },
              inputs: {
                type: "object",
                properties: {
                  order_id: { type: "string" }
                },
                required: ["order_id"]
              },
              outputs: {
                type: "object",
                properties: {
                  order_id: { type: "string" },
                  status: { type: "string" }
                }
              },
              safety_rules: [
                "Never cancel executed orders",
                "Verify order status before cancellation"
              ]
            },
            handler: lambda { |args|
              if ENV["DRY_RUN"] == "true" || ENV["DRY_RUN_MODE"] == "true"
                {
                  order_id: args[:order_id] || args["order_id"],
                  status: "DRY_RUN_CANCELLED",
                  message: "Order cancellation simulated"
                }
              else
                begin
                  order = DhanHQ::Models::Order.find(args[:order_id] || args["order_id"])
                  order.cancel
                  { order_id: order.order_id, status: "CANCELLED" }
                rescue StandardError => e
                  { order_id: nil, status: "error", error: e.message }
                end
              end
            }
          )

          # 17. Exit Position
          registry.register(
            descriptor: {
              name: "dhan.position.exit",
              category: "trade",
              description: "Exits an open position by placing opposite order",
              when_to_use: "When closing a position manually",
              when_not_to_use: "If stop-loss or target will handle exit",
              risk_level: :high,
              side_effects: ["REAL MONEY ORDER"],
              dependencies: {
                required_outputs: [
                  "position_exists"
                ],
                required_guards: [
                  "PositionGuard"
                ],
                forbidden_after: [
                  "position_closed"
                ]
              },
              inputs: {
                type: "object",
                properties: {
                  security_id: { type: "string" },
                  quantity: { type: "integer" },
                  order_type: {
                    type: "string",
                    enum: %w[MARKET LIMIT]
                  },
                  price: { type: "number", nullable: true }
                },
                required: %w[security_id quantity order_type]
              },
              outputs: {
                type: "object",
                properties: {
                  order_id: { type: "string" },
                  status: { type: "string" }
                }
              },
              safety_rules: [
                "Verify position exists before exit",
                "Never exit more than position size"
              ]
            },
            handler: lambda { |args|
              if ENV["DRY_RUN"] == "true" || ENV["DRY_RUN_MODE"] == "true"
                {
                  order_id: "SIMULATED_EXIT_#{Time.now.to_i}",
                  status: "DRY_RUN",
                  message: "Position exit simulated"
                }
              else
                begin
                  # Find position and place opposite order
                  positions = if DhanHQ::Models::Position.respond_to?(:all)
                                DhanHQ::Models::Position.all
                              elsif DhanHQ::Models::Position.respond_to?(:list)
                                DhanHQ::Models::Position.list
                              else
                                []
                              end
                  position = positions.find { |p| p.security_id == (args[:security_id] || args["security_id"]) }

                  return { order_id: nil, status: "error", error: "Position not found" } unless position

                  # Determine opposite transaction type
                  opposite_type = position.transaction_type == "BUY" ? "SELL" : "BUY"

                  order = DhanHQ::Models::Order.new(
                    transaction_type: opposite_type,
                    exchange_segment: position.exchange_segment,
                    product_type: position.product_type,
                    order_type: args[:order_type] || args["order_type"],
                    security_id: args[:security_id] || args["security_id"],
                    quantity: args[:quantity] || args["quantity"],
                    price: args[:price] || args["price"]
                  )
                  order.save
                  { order_id: order.order_id, status: order.status }
                rescue StandardError => e
                  { order_id: nil, status: "error", error: e.message }
                end
              end
            }
          )
        end

        # ============================================
        # SUPER ORDER TOOLS (WRITE - HIGH RISK)
        # ============================================

        def self.register_super_order_tools(registry, dhan_client)
          # 18. Place Super Order (Preferred for Options)
          registry.register(
            descriptor: {
              name: "dhan.super.place",
              category: "trade",
              description: "Places a Super Order with built-in stop-loss and target",
              when_to_use: "Preferred execution for options buying with SL/TP",
              when_not_to_use: "If SL cannot be defined or for manual SL management",
              risk_level: :high,
              side_effects: ["REAL MONEY ORDER WITH LEGS"],
              inputs: {
                type: "object",
                properties: {
                  transaction_type: {
                    type: "string",
                    enum: ["BUY"]
                  },
                  exchange_segment: { type: "string" },
                  product_type: { type: "string" },
                  order_type: {
                    type: "string",
                    enum: %w[MARKET LIMIT]
                  },
                  security_id: { type: "string" },
                  quantity: {
                    type: "integer",
                    minimum: 1
                  },
                  price: { type: "number" },
                  target_price: {
                    type: "number",
                    nullable: true,
                    description: "Target price (optional)"
                  },
                  stop_loss_price: {
                    type: "number",
                    description: "Stop-loss price (required)"
                  },
                  trailing_jump: {
                    type: "number",
                    nullable: true,
                    description: "Trailing stop jump (optional)"
                  }
                },
                required: %w[transaction_type exchange_segment product_type order_type security_id quantity price
                             stop_loss_price]
              },
              outputs: {
                type: "object",
                properties: {
                  order_id: { type: "string" },
                  order_status: { type: "string" }
                }
              },
              safety_rules: [
                "Stop-loss is MANDATORY",
                "Never place without risk validation",
                "Verify funds before placing"
              ]
            },
            handler: lambda { |args|
              if ENV["DRY_RUN"] == "true" || ENV["DRY_RUN_MODE"] == "true"
                {
                  order_id: "SIMULATED_SUPER_#{Time.now.to_i}",
                  order_status: "DRY_RUN",
                  message: "Super order simulated - dry-run mode active"
                }
              else
                begin
                  if defined?(DhanHQ::Models::SuperOrder) && DhanHQ::Models::SuperOrder.respond_to?(:create)
                    DhanHQ::Models::SuperOrder.create(
                      transaction_type: args[:transaction_type] || args["transaction_type"],
                      exchange_segment: args[:exchange_segment] || args["exchange_segment"],
                      product_type: args[:product_type] || args["product_type"],
                      order_type: args[:order_type] || args["order_type"],
                      security_id: args[:security_id] || args["security_id"],
                      quantity: args[:quantity] || args["quantity"],
                      price: args[:price] || args["price"],
                      target_price: args[:target_price] || args["target_price"],
                      stop_loss_price: args[:stop_loss_price] || args["stop_loss_price"],
                      trailing_jump: args[:trailing_jump] || args["trailing_jump"]
                    )
                  else
                    { order_id: nil, order_status: "error", error: "SuperOrder not available" }
                  end
                rescue StandardError => e
                  { order_id: nil, order_status: "error", error: e.message }
                end
              end
            }
          )

          # 19. Modify Super Order
          registry.register(
            descriptor: {
              name: "dhan.super.modify",
              category: "trade",
              description: "Modifies stop-loss or target of a Super Order",
              when_to_use: "When adjusting SL/TP levels",
              when_not_to_use: "If order already executed",
              risk_level: :high,
              side_effects: ["MODIFIES REAL SUPER ORDER"],
              dependencies: {
                required_outputs: [
                  "order_id"
                ],
                max_calls_per_trade: 1
              },
              inputs: {
                type: "object",
                properties: {
                  order_id: { type: "string" },
                  target_price: { type: "number", nullable: true },
                  stop_loss_price: { type: "number", nullable: true },
                  trailing_jump: { type: "number", nullable: true }
                },
                required: ["order_id"]
              },
              outputs: {
                type: "object",
                properties: {
                  order_id: { type: "string" },
                  status: { type: "string" }
                }
              },
              safety_rules: [
                "Never modify executed orders",
                "Stop-loss adjustment must be safer (wider)"
              ]
            },
            handler: lambda { |args|
              if ENV["DRY_RUN"] == "true" || ENV["DRY_RUN_MODE"] == "true"
                {
                  order_id: args[:order_id] || args["order_id"],
                  status: "DRY_RUN_MODIFIED",
                  message: "Super order modification simulated"
                }
              else
                begin
                  if defined?(DhanHQ::Models::SuperOrder) && DhanHQ::Models::SuperOrder.respond_to?(:modify)
                    DhanHQ::Models::SuperOrder.modify(
                      order_id: args[:order_id] || args["order_id"],
                      target_price: args[:target_price] || args["target_price"],
                      stop_loss_price: args[:stop_loss_price] || args["stop_loss_price"],
                      trailing_jump: args[:trailing_jump] || args["trailing_jump"]
                    )
                  else
                    { order_id: nil, status: "error", error: "SuperOrder modify not available" }
                  end
                rescue StandardError => e
                  { order_id: nil, status: "error", error: e.message }
                end
              end
            }
          )

          # 20. Cancel Super Order
          registry.register(
            descriptor: {
              name: "dhan.super.cancel",
              category: "trade",
              description: "Cancels a Super Order",
              when_to_use: "When order is no longer needed",
              when_not_to_use: "If order already executed",
              risk_level: :high,
              side_effects: ["CANCELS REAL SUPER ORDER"],
              dependencies: {
                required_outputs: [
                  "order_id"
                ],
                max_calls_per_trade: 1
              },
              inputs: {
                type: "object",
                properties: {
                  order_id: { type: "string" }
                },
                required: ["order_id"]
              },
              outputs: {
                type: "object",
                properties: {
                  order_id: { type: "string" },
                  status: { type: "string" }
                }
              },
              safety_rules: [
                "Never cancel executed orders",
                "Verify order status before cancellation"
              ]
            },
            handler: lambda { |args|
              if ENV["DRY_RUN"] == "true" || ENV["DRY_RUN_MODE"] == "true"
                {
                  order_id: args[:order_id] || args["order_id"],
                  status: "DRY_RUN_CANCELLED",
                  message: "Super order cancellation simulated"
                }
              else
                begin
                  if defined?(DhanHQ::Models::SuperOrder) && DhanHQ::Models::SuperOrder.respond_to?(:cancel)
                    DhanHQ::Models::SuperOrder.cancel(args[:order_id] || args["order_id"])
                  else
                    { order_id: nil, status: "error", error: "SuperOrder cancel not available" }
                  end
                rescue StandardError => e
                  { order_id: nil, status: "error", error: e.message }
                end
              end
            }
          )
        end

        # ============================================
        # CACHE TOOLS (READ - WebSocket Data)
        # ============================================

        def self.register_cache_tools(registry, cache_store)
          # 21. Cache LTP (from WebSocket)
          registry.register(
            descriptor: {
              name: "dhan.cache.ltp",
              category: "cache",
              description: "Gets LTP from WebSocket cache (faster than API call)",
              when_to_use: "For fast price checks during live trading",
              when_not_to_use: "If WebSocket not connected or cache stale",
              risk_level: :none,
              inputs: {
                type: "object",
                properties: {
                  security_id: { type: "string" }
                },
                required: ["security_id"]
              },
              outputs: {
                type: "object",
                properties: {
                  ltp: { type: "number" },
                  timestamp: { type: "string" },
                  cached: { type: "boolean" }
                }
              },
              side_effects: [],
              safety_rules: []
            },
            handler: lambda { |args|
              if cache_store
                cached = cache_store.get("ltp:#{args[:security_id] || args["security_id"]}")
                if cached
                  { ltp: cached[:ltp] || cached["ltp"] || 0, timestamp: cached[:timestamp] || cached["timestamp"],
                    cached: true }
                else
                  { ltp: 0, timestamp: Time.now.iso8601, cached: false, error: "Not in cache" }
                end
              else
                { ltp: 0, timestamp: Time.now.iso8601, cached: false, error: "Cache store not configured" }
              end
            }
          )

          # 22. Cache Tick (from WebSocket)
          registry.register(
            descriptor: {
              name: "dhan.cache.tick",
              category: "cache",
              description: "Gets latest tick data from WebSocket cache",
              when_to_use: "For real-time bid/ask during execution",
              when_not_to_use: "If WebSocket not connected",
              risk_level: :none,
              inputs: {
                type: "object",
                properties: {
                  security_id: { type: "string" }
                },
                required: ["security_id"]
              },
              outputs: {
                type: "object",
                properties: {
                  ltp: { type: "number" },
                  bid: { type: "number" },
                  ask: { type: "number" },
                  volume: { type: "number" },
                  timestamp: { type: "string" },
                  cached: { type: "boolean" }
                }
              },
              side_effects: [],
              safety_rules: []
            },
            handler: lambda { |args|
              if cache_store
                cached = cache_store.get("tick:#{args[:security_id] || args["security_id"]}")
                if cached
                  {
                    ltp: cached[:ltp] || cached["ltp"] || 0,
                    bid: cached[:bid] || cached["bid"] || 0,
                    ask: cached[:ask] || cached["ask"] || 0,
                    volume: cached[:volume] || cached["volume"] || 0,
                    timestamp: cached[:timestamp] || cached["timestamp"],
                    cached: true
                  }
                else
                  { ltp: 0, bid: 0, ask: 0, volume: 0, timestamp: Time.now.iso8601, cached: false,
                    error: "Not in cache" }
                end
              else
                { ltp: 0, bid: 0, ask: 0, volume: 0, timestamp: Time.now.iso8601, cached: false,
                  error: "Cache store not configured" }
              end
            }
          )
        end

        # ============================================
        # HELPER METHODS
        # ============================================

        # Transform raw API response to production-grade candle format with complete flag
        # Returns: { candles: [...], interval: "...", complete: true/false }
        def self.transform_to_candles_with_complete(raw_data, interval)
          return { candles: [], complete: false } if raw_data.nil? || raw_data.empty?

          # Check if data is already in candle array format
          if raw_data.is_a?(Array) && raw_data.first.is_a?(Hash)
            candles = raw_data.map do |candle|
              {
                ts: parse_timestamp(candle[:time] || candle["time"] || candle[:ts] || candle["ts"] || candle[:timestamp] || candle["timestamp"]),
                open: candle[:open] || candle["open"] || 0,
                high: candle[:high] || candle["high"] || 0,
                low: candle[:low] || candle["low"] || 0,
                close: candle[:close] || candle["close"] || 0,
                volume: candle[:volume] || candle["volume"] || 0,
                open_interest: candle[:open_interest] || candle["open_interest"] || nil
              }.compact
            end

            # Determine if last candle is complete
            complete = determine_candle_completeness(candles, interval)

            { candles: candles, complete: complete }
          else
            # Transform from DhanHQ format: {"open"=>[val1, val2], "high"=>[val1, val2], "timestamp"=>[ts1, ts2], "volume"=>[v1, v2], ...}
            required_keys = %w[open high low close]
            return { candles: [], complete: false } unless required_keys.all? { |k| raw_data[k] || raw_data[k.to_sym] }

            length = (raw_data["open"] || raw_data[:open])&.length || 0
            return { candles: [], complete: false } if length.zero?

            # Extract arrays (handle both string and symbol keys)
            open_arr = raw_data["open"] || raw_data[:open] || []
            high_arr = raw_data["high"] || raw_data[:high] || []
            low_arr = raw_data["low"] || raw_data[:low] || []
            close_arr = raw_data["close"] || raw_data[:close] || []
            volume_arr = raw_data["volume"] || raw_data[:volume] || []
            timestamp_arr = raw_data["timestamp"] || raw_data[:timestamp] || []
            oi_arr = raw_data["open_interest"] || raw_data[:open_interest] || []

            candles = (0...length).map do |i|
              candle = {
                ts: parse_timestamp(timestamp_arr[i] || raw_data["time"]&.[](i) || raw_data[:time]&.[](i) || raw_data["ts"]&.[](i) || raw_data[:ts]&.[](i)),
                open: open_arr[i] || 0,
                high: high_arr[i] || 0,
                low: low_arr[i] || 0,
                close: close_arr[i] || 0
              }

              # Add volume if available (volume array exists and has data for this index)
              if volume_arr.is_a?(Array) && volume_arr.length > 0 && i < volume_arr.length
                candle[:volume] = volume_arr[i] || 0
              end

              # Add open_interest if available (for F&O instruments, only if non-zero)
              if oi_arr.is_a?(Array) && oi_arr.length > 0 && i < oi_arr.length && oi_arr[i] && oi_arr[i] != 0
                candle[:open_interest] = oi_arr[i]
              end

              candle
            end

            complete = determine_candle_completeness(candles, interval)
            { candles: candles, complete: complete }
          end
        end

        # Parse timestamp to epoch integer
        def self.parse_timestamp(time_value)
          return Time.now.to_i if time_value.nil?

          case time_value
          when Integer
            time_value
          when String
            Time.parse(time_value).to_i
          when Time
            time_value.to_i
          else
            Time.now.to_i
          end
        rescue StandardError
          Time.now.to_i
        end

        # Determine if last candle is complete (closed)
        # Rules:
        # - If market is closed, last candle is complete
        # - If current time is past the candle's end time + buffer, it's complete
        # - For safety, assume incomplete if uncertain
        def self.determine_candle_completeness(candles, interval)
          return false if candles.empty?

          now = Time.now
          interval_minutes = interval.to_i

          # Market hours: 9:15 AM to 3:30 PM IST
          market_open = Time.new(now.year, now.month, now.day, 9, 15, 0, "+05:30")
          market_close = Time.new(now.year, now.month, now.day, 15, 30, 0, "+05:30")

          # If market is closed, all candles are complete
          return true if now > market_close || now < market_open

          # Get last candle timestamp
          last_ts = candles.last[:ts]
          last_candle_time = Time.at(last_ts)

          # Candle is complete if current time is past candle end + buffer
          candle_end = last_candle_time + (interval_minutes * 60)
          buffer_seconds = 60 # 1 minute buffer
          now > (candle_end + buffer_seconds)
        end

        # Transform raw API response to candle array format (legacy method for backward compatibility)
        def self.transform_to_candles(raw_data)
          return [] if raw_data.nil? || raw_data.empty?

          # If already in candle array format
          if raw_data.is_a?(Array) && raw_data.first.is_a?(Hash) && (raw_data.first.key?("open") || raw_data.first.key?(:open))
            return raw_data
          end

          # Transform from API format {open: [], high: [], ...} to [{open: val, high: val, ...}, ...]
          if raw_data.is_a?(Hash)
            keys = raw_data.keys.map(&:to_s)
            length = raw_data[keys.first]&.length || 0

            (0...length).map do |i|
              keys.each_with_object({}) do |key, candle|
                candle[key] = raw_data[key][i] if raw_data[key]
              end
            end
          else
            []
          end
        end
      end
    end
  end
end
