# frozen_string_literal: true

# Enhanced DhanHQ tool descriptors with examples, safety rules, and full metadata
# Production-grade tool definitions following ToolDescriptor schema

module Vyapari
  module Tools
    class EnhancedDhanTools
      # Get all tool descriptors in standardized format
      def self.all
        [
          market_ltp,
          market_quote,
          instrument_find,
          option_chain,
          option_expiries,
          history_intraday,
          history_daily,
          funds_balance,
          positions_list,
          orders_list,
          place_order,
          super_place
        ]
      end

      # Market LTP
      def self.market_ltp
        {
          name: "dhan.market.ltp",
          category: "market.read",
          description: "Fetch latest traded price (LTP) for an instrument",
          purpose: "Get current price for entry, SL calculation, or validation",

          when_to_use: [
            "Need current price for calculation",
            "Validating SL or entry logic",
            "Checking if price has moved significantly"
          ],
          when_not_to_use: [
            "Inside WebSocket tick handler (use cached price)",
            "If price already cached and market hasn't moved",
            "Repeatedly in the same iteration"
          ],

          inputs: {
            type: "object",
            properties: {
              exchange_segment: {
                type: "string",
                enum: %w[IDX_I NSE_EQ NSE_FNO NSE_CURRENCY BSE_EQ MCX_COMM BSE_CURRENCY BSE_FNO],
                examples: %w[NSE_FNO IDX_I],
                description: "Exchange segment code (IDX_I=Index, NSE_FNO=NSE F&O, NSE_EQ=NSE Equity, etc.)"
              },
              security_id: {
                type: "string",
                examples: %w[13 12345],
                description: "DhanHQ security ID"
              }
            },
            required: %w[exchange_segment security_id]
          },

          outputs: {
            type: "object",
            properties: {
              ltp: {
                type: "number",
                examples: [102.5, 22_450.0],
                description: "Latest traded price"
              },
              timestamp: {
                type: "string",
                format: "date-time",
                examples: ["2024-01-15T10:30:00+05:30"]
              }
            },
            required: ["ltp"]
          },

          side_effects: [],
          safety_rules: [
            "Do not poll excessively (rate limit: 10 calls/minute)",
            "Prefer cached LTP when available from WebSocket"
          ],

          examples: {
            valid: [
              {
                input: {
                  exchange_segment: "IDX_I",
                  security_id: "13"
                },
                comment: "Fetch NIFTY index current value"
              },
              {
                input: {
                  exchange_segment: "NSE_FNO",
                  security_id: "12345"
                },
                comment: "Fetch option contract LTP"
              }
            ],
            invalid: [
              {
                input: {
                  security_id: "13"
                },
                reason: "exchange_segment is required"
              },
              {
                input: {
                  exchange_segment: "INVALID",
                  security_id: "13"
                },
                reason: "Invalid exchange_segment (must be valid enum value)"
              }
            ]
          }
        }
      end

      # Market Quote
      def self.market_quote
        {
          name: "dhan.market.quote",
          category: "market.read",
          description: "Fetch full market quote including bid/ask, volume, OI",
          purpose: "Analyze liquidity, spread, and market depth before entry",

          when_to_use: [
            "Analyzing liquidity before entry",
            "Checking bid-ask spread",
            "Verifying open interest for options"
          ],
          when_not_to_use: [
            "If only price is needed (use LTP)",
            "Inside tight loops (use LTP instead)"
          ],

          inputs: {
            type: "object",
            properties: {
              exchange_segment: { type: "string",
                                  enum: %w[IDX_I NSE_EQ NSE_FNO NSE_CURRENCY BSE_EQ MCX_COMM
                                           BSE_CURRENCY BSE_FNO] },
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
          safety_rules: [],

          examples: {
            valid: [
              {
                input: {
                  exchange_segment: "NSE_FNO",
                  security_id: "12345"
                },
                comment: "Get full quote for option contract"
              }
            ],
            invalid: []
          }
        }
      end

      # Instrument Find
      def self.instrument_find
        {
          name: "dhan.instrument.find",
          category: "market.read",
          description: "Find instrument and trading metadata by symbol",
          purpose: "Resolve symbols to security_id before analysis or trading",

          when_to_use: [
            "Resolving symbols before analysis",
            "Getting instrument details",
            "Finding security_id for API calls"
          ],
          when_not_to_use: [
            "If security_id already known",
            "Repeatedly for the same symbol"
          ],

          inputs: {
            type: "object",
            properties: {
              exchange_segment: {
                type: "string",
                enum: %w[IDX_I NSE_EQ NSE_FNO NSE_CURRENCY BSE_EQ MCX_COMM BSE_CURRENCY BSE_FNO],
                examples: %w[IDX_I NSE_EQ]
              },
              symbol: {
                type: "string",
                examples: %w[NIFTY RELIANCE NIFTY25JAN22500CE]
              }
            },
            required: %w[exchange_segment symbol]
          },

          outputs: {
            type: "object",
            properties: {
              security_id: { type: "string", examples: %w[13 12345] },
              instrument_type: {
                type: "string",
                enum: %w[INDEX FUTIDX OPTIDX EQUITY FUTSTK OPTSTK FUTCOM OPTFUT FUTCUR OPTCUR],
                examples: %w[INDEX OPTIDX EQUITY]
              },
              symbol: { type: "string" },
              exchange_segment: { type: "string" }
            },
            required: ["security_id"]
          },

          side_effects: [],
          safety_rules: [],

          examples: {
            valid: [
              {
                input: {
                  exchange_segment: "IDX_I",
                  symbol: "NIFTY"
                },
                comment: "Find NIFTY index instrument"
              },
              {
                input: {
                  exchange_segment: "NSE_FNO",
                  symbol: "NIFTY25JAN22500CE"
                },
                comment: "Find option contract"
              }
            ],
            invalid: [
              {
                input: {
                  symbol: "NIFTY"
                },
                reason: "exchange_segment is required"
              }
            ]
          }
        }
      end

      # Option Chain
      def self.option_chain
        {
          name: "dhan.option.chain",
          category: "options.read",
          description: "Fetch option chain for an expiry with strikes, premiums, Greeks",
          purpose: "Strike selection and IV analysis in options intraday mode",

          when_to_use: [
            "Strike selection in options intraday mode",
            "Analyzing IV and Greeks",
            "Finding ATM strike"
          ],
          when_not_to_use: [
            "After order execution",
            "Repeatedly in the same iteration",
            "If chain already cached"
          ],

          inputs: {
            type: "object",
            properties: {
              underlying_scrip: {
                type: "integer",
                examples: [13],
                description: "Underlying security_id (integer, e.g., 13 for NIFTY). Must be an integer."
              },
              underlying_seg: {
                type: "string",
                enum: ["IDX_I"],
                examples: ["IDX_I"],
                description: "Underlying segment (IDX_I for indices)"
              },
              expiry: {
                type: "string",
                format: "date",
                examples: ["2025-01-30"],
                description: "Expiry date (YYYY-MM-DD format). Optional - if not provided, will be automatically resolved from expiry list using nearest expiry >= today."
              }
            },
            required: %w[underlying_scrip underlying_seg]
          },

          outputs: {
            type: "object",
            properties: {
              contracts: {
                type: "array",
                description: "Array of option contracts with strikes, premiums, Greeks"
              },
              spot_price: {
                type: "number",
                examples: [22_450.0],
                description: "Current underlying spot price"
              }
            },
            required: %w[contracts spot_price]
          },

          side_effects: [],
          safety_rules: [
            "Consider only ±1-2 strikes from ATM",
            "Do not scan entire chain (creates noise)",
            "Cache chain data to avoid repeated calls"
          ],

          examples: {
            valid: [
              {
                input: {
                  underlying_scrip: "13",
                  underlying_seg: "IDX_I",
                  expiry: "2025-01-30"
                },
                comment: "Fetch NIFTY weekly option chain"
              }
            ],
            invalid: [
              {
                input: {
                  underlying_scrip: "NIFTY"
                },
                reason: "expiry and underlying_seg missing"
              },
              {
                input: {
                  underlying_scrip: "13",
                  underlying_seg: "IDX_I",
                  expiry: "invalid-date"
                },
                reason: "expiry must be valid YYYY-MM-DD format"
              }
            ]
          }
        }
      end

      # Option Expiries
      def self.option_expiries
        {
          name: "dhan.option.expiries",
          category: "options.read",
          description: "Get available expiry dates for an underlying",
          purpose: "Find valid expiry before fetching option chain",

          when_to_use: [
            "Before fetching option chain",
            "Finding next weekly/monthly expiry"
          ],
          when_not_to_use: [
            "If expiry already known",
            "Repeatedly for same underlying"
          ],

          inputs: {
            type: "object",
            properties: {
              underlying_scrip: {
                type: "integer",
                examples: [13],
                description: "Underlying security_id (integer, e.g., 13 for NIFTY). Must be an integer."
              },
              underlying_seg: { type: "string", enum: ["IDX_I"] },
              expiry: {
                type: "string",
                description: "Any valid expiry date (YYYY-MM-DD format). Required by API but can be any date."
              }
            },
            required: %w[underlying_scrip underlying_seg]
          },

          outputs: {
            type: "object",
            properties: {
              expiries: {
                type: "array",
                items: { type: "string", format: "date" },
                examples: [%w[2025-01-30 2025-02-06]]
              }
            },
            required: ["expiries"]
          },

          side_effects: [],
          safety_rules: [
            "Use first valid expiry (not passed after 4 PM)"
          ],

          examples: {
            valid: [
              {
                input: {
                  underlying_scrip: "13",
                  underlying_seg: "IDX_I"
                },
                comment: "Get NIFTY expiry list"
              }
            ],
            invalid: []
          }
        }
      end

      # History Intraday
      def self.history_intraday
        {
          name: "dhan.history.intraday",
          category: "market.read",
          description: "Fetch intraday OHLC candles for analysis",
          purpose: "Multi-timeframe analysis (15m, 5m, 1m for options)",

          when_to_use: [
            "MTF analysis in Agent A",
            "Structure and momentum analysis"
          ],
          when_not_to_use: [
            "After analysis complete",
            "Repeatedly for same timeframe"
          ],

          inputs: {
            type: "object",
            properties: {
              security_id: { type: "string" },
              exchange_segment: { type: "string" },
              instrument: { type: "string" },
              interval: {
                type: "string",
                enum: %w[1 5 15 30 60],
                examples: %w[15 5 1],
                description: "Candle interval in minutes"
              },
              from_date: { type: "string", format: "date" },
              to_date: { type: "string", format: "date" }
            },
            required: %w[security_id exchange_segment instrument interval]
          },

          outputs: {
            type: "object",
            properties: {
              candles: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    open: { type: "number" },
                    high: { type: "number" },
                    low: { type: "number" },
                    close: { type: "number" },
                    volume: { type: "number" },
                    timestamp: { type: "string" }
                  }
                }
              }
            },
            required: ["candles"]
          },

          side_effects: [],
          safety_rules: [],

          examples: {
            valid: [
              {
                input: {
                  security_id: "13",
                  exchange_segment: "IDX_I",
                  instrument: "NIFTY",
                  interval: "15"
                },
                comment: "Fetch 15m candles for NIFTY"
              }
            ],
            invalid: []
          }
        }
      end

      # History Daily
      def self.history_daily
        {
          name: "dhan.history.daily",
          category: "market.read",
          description: "Fetch daily OHLC candles for swing trading",
          purpose: "Primary trend analysis (1D timeframe)",

          when_to_use: [
            "Swing trading mode (1D analysis)",
            "Trend and structure analysis"
          ],
          when_not_to_use: [
            "Options intraday mode",
            "If daily data already cached"
          ],

          inputs: {
            type: "object",
            properties: {
              security_id: { type: "string" },
              exchange_segment: { type: "string" },
              instrument: { type: "string" },
              from_date: { type: "string", format: "date" },
              to_date: { type: "string", format: "date" }
            },
            required: %w[security_id exchange_segment instrument]
          },

          outputs: {
            type: "object",
            properties: {
              candles: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    open: { type: "number" },
                    high: { type: "number" },
                    low: { type: "number" },
                    close: { type: "number" },
                    volume: { type: "number" },
                    date: { type: "string", format: "date" }
                  }
                }
              }
            },
            required: ["candles"]
          },

          side_effects: [],
          safety_rules: [],

          examples: {
            valid: [
              {
                input: {
                  security_id: "123",
                  exchange_segment: "NSE_EQ",
                  instrument: "RELIANCE"
                },
                comment: "Fetch daily candles for swing analysis"
              }
            ],
            invalid: []
          }
        }
      end

      # Funds Balance
      def self.funds_balance
        {
          name: "dhan.funds.balance",
          category: "risk.read",
          description: "Check available margin and funds",
          purpose: "Validate sufficient capital before trade execution",

          when_to_use: [
            "Agent B risk validation",
            "Before calculating lot size"
          ],
          when_not_to_use: [
            "During market analysis",
            "Repeatedly in same validation"
          ],

          inputs: {
            type: "object",
            properties: {}
          },

          outputs: {
            type: "object",
            properties: {
              available_margin: { type: "number", examples: [85_000.0] },
              utilized_margin: { type: "number" },
              total_margin: { type: "number" }
            },
            required: ["available_margin"]
          },

          side_effects: [],
          safety_rules: [],

          examples: {
            valid: [
              {
                input: {},
                comment: "Get current account balance"
              }
            ],
            invalid: []
          }
        }
      end

      # Positions List
      def self.positions_list
        {
          name: "dhan.positions.list",
          category: "risk.read",
          description: "List current open positions",
          purpose: "Check for duplicate positions or existing exposure",

          when_to_use: [
            "Agent B validation",
            "Checking for duplicate positions"
          ],
          when_not_to_use: [
            "During market analysis",
            "Inside position tracking (use WebSocket)"
          ],

          inputs: {
            type: "object",
            properties: {}
          },

          outputs: {
            type: "object",
            properties: {
              positions: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    security_id: { type: "string" },
                    quantity: { type: "number" },
                    average_price: { type: "number" }
                  }
                }
              }
            },
            required: ["positions"]
          },

          side_effects: [],
          safety_rules: [],

          examples: {
            valid: [
              {
                input: {},
                comment: "Get all open positions"
              }
            ],
            invalid: []
          }
        }
      end

      # Orders List
      def self.orders_list
        {
          name: "dhan.orders.list",
          category: "risk.read",
          description: "List recent orders",
          purpose: "Check for duplicate orders or pending executions",

          when_to_use: [
            "Agent C pre-execution check",
            "Verifying no duplicate orders"
          ],
          when_not_to_use: [
            "During analysis",
            "Repeatedly in same check"
          ],

          inputs: {
            type: "object",
            properties: {}
          },

          outputs: {
            type: "object",
            properties: {
              orders: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    order_id: { type: "string" },
                    status: { type: "string" },
                    security_id: { type: "string" }
                  }
                }
              }
            },
            required: ["orders"]
          },

          side_effects: [],
          safety_rules: [],

          examples: {
            valid: [
              {
                input: {},
                comment: "Get recent orders"
              }
            ],
            invalid: []
          }
        }
      end

      # Place Order (Standard)
      def self.place_order
        {
          name: "dhan.order.place",
          category: "trade.execution",
          description: "Place a standard BUY options order",
          purpose: "Execute a validated trade decision (fallback if Super Order not supported)",

          when_to_use: [
            "Trade approved by Risk Agent",
            "Super order not supported by instrument"
          ],
          when_not_to_use: [
            "During analysis or planning",
            "If stop-loss not defined",
            "If Super Order is available (prefer super.place)"
          ],

          inputs: {
            type: "object",
            properties: {
              symbol: {
                type: "string",
                examples: ["NIFTY25JAN22500CE"],
                description: "Option contract symbol"
              },
              exchange_segment: {
                type: "string",
                enum: ["NSE_FNO"],
                description: "Exchange segment (NSE_FNO for NSE Futures & Options)"
              },
              product_type: {
                type: "string",
                enum: %w[INTRADAY MARGIN],
                examples: ["INTRADAY"],
                description: "Product type (INTRADAY for intraday, MARGIN for carry forward)"
              },
              transaction_type: {
                type: "string",
                enum: ["BUY"],
                description: "Only BUY allowed for options buying"
              },
              quantity: {
                type: "integer",
                minimum: 1,
                examples: [75, 150, 300],
                description: "Must be multiple of lot size (NIFTY=75, SENSEX=20)"
              },
              order_type: {
                type: "string",
                enum: %w[MARKET LIMIT],
                description: "Order type"
              },
              price: {
                type: "number",
                nullable: true,
                examples: [120.5],
                description: "Required only for LIMIT orders"
              }
            },
            required: %w[symbol exchange_segment product_type transaction_type quantity order_type]
          },

          outputs: {
            type: "object",
            properties: {
              order_id: {
                type: "string",
                examples: ["112111182198"]
              },
              status: {
                type: "string",
                enum: %w[TRANSIT PENDING CLOSED TRIGGERED REJECTED CANCELLED PART_TRADED TRADED],
                examples: %w[PENDING TRADED REJECTED]
              }
            },
            required: %w[order_id status]
          },

          side_effects: [
            "Places REAL money order if dry_run=false",
            "Order cannot be undone once executed"
          ],

          safety_rules: [
            "Stop-loss must already be planned (not in this order)",
            "Quantity must be multiple of instrument lot size",
            "Quantity must not exceed max allowed lots (6 for NIFTY)",
            "Do not retry more than once",
            "Never place without Agent B approval"
          ],

          defaults: {
            order_type: "MARKET",
            exchange_segment: "NSE_FNO",
            product_type: "INTRADAY"
          },

          dry_run_behavior: {
            enabled: true,
            returns: {
              order_id: "SIMULATED_ORDER",
              status: "DRY_RUN"
            }
          },

          examples: {
            valid: [
              {
                input: {
                  symbol: "NIFTY25JAN22500CE",
                  exchange_segment: "NSE_FNO",
                  product_type: "INTRADAY",
                  transaction_type: "BUY",
                  quantity: 150,
                  order_type: "MARKET"
                },
                comment: "2-lot NIFTY CE buy (150 = 2 × 75)"
              },
              {
                input: {
                  symbol: "NIFTY25JAN22500CE",
                  exchange_segment: "NSE_FNO",
                  product_type: "INTRADAY",
                  transaction_type: "BUY",
                  quantity: 75,
                  order_type: "LIMIT",
                  price: 120.5
                },
                comment: "1-lot limit order"
              }
            ],
            invalid: [
              {
                input: {
                  symbol: "NIFTY",
                  quantity: 10
                },
                reason: "Invalid symbol format and quantity not multiple of lot size"
              },
              {
                input: {
                  symbol: "NIFTY25JAN22500CE",
                  transaction_type: "SELL"
                },
                reason: "SELL not allowed in options buying mode"
              },
              {
                input: {
                  symbol: "NIFTY25JAN22500CE",
                  quantity: 100
                },
                reason: "Quantity 100 is not multiple of NIFTY lot size (75)"
              }
            ]
          }
        }
      end

      # Super Place (Preferred)
      def self.super_place
        {
          name: "dhan.super.place",
          category: "trade.execution",
          description: "Place Super Order with integrated SL/TP (PREFERRED)",
          purpose: "Execute trade with stop-loss and target in single order",

          when_to_use: [
            "Trade approved by Risk Agent",
            "SL and TP are finalized",
            "Instrument supports Super Orders"
          ],
          when_not_to_use: [
            "During analysis",
            "If SL/TP not defined",
            "If Super Order not supported (fallback to order.place)"
          ],

          inputs: {
            type: "object",
            properties: {
              security_id: {
                type: "string",
                examples: ["12346"],
                description: "Option contract security_id"
              },
              exchange_segment: {
                type: "string",
                enum: ["NSE_FNO"]
              },
              product_type: {
                type: "string",
                enum: %w[INTRADAY MARGIN],
                examples: ["INTRADAY"],
                description: "Product type (INTRADAY for intraday, MARGIN for carry forward)"
              },
              transaction_type: {
                type: "string",
                enum: ["BUY"]
              },
              quantity: {
                type: "integer",
                minimum: 1,
                examples: [75, 150]
              },
              order_type: {
                type: "string",
                enum: %w[MARKET LIMIT]
              },
              price: {
                type: "number",
                nullable: true
              },
              stop_loss: {
                type: "number",
                examples: [85.0],
                description: "Stop-loss price (MANDATORY)"
              },
              target: {
                type: "number",
                examples: [130.75],
                description: "Target price (MANDATORY)"
              }
            },
            required: %w[security_id exchange_segment product_type transaction_type quantity order_type stop_loss
                         target]
          },

          outputs: {
            type: "object",
            properties: {
              order_id: { type: "string" },
              status: { type: "string" }
            },
            required: %w[order_id status]
          },

          side_effects: [
            "Places REAL money order with SL/TP",
            "Order cannot be undone once executed"
          ],

          safety_rules: [
            "Stop-loss is MANDATORY",
            "Target is MANDATORY",
            "Quantity must be multiple of lot size",
            "Do not retry more than once",
            "Never place without Agent B approval"
          ],

          dry_run_behavior: {
            enabled: true,
            returns: {
              order_id: "SIMULATED_SUPER_ORDER",
              status: "DRY_RUN"
            }
          },

          examples: {
            valid: [
              {
                input: {
                  security_id: "12346",
                  exchange_segment: "NSE_FNO",
                  product_type: "INTRADAY",
                  transaction_type: "BUY",
                  quantity: 75,
                  order_type: "MARKET",
                  stop_loss: 85.0,
                  target: 130.75
                },
                comment: "Super Order with SL ₹85 and TP ₹130.75"
              }
            ],
            invalid: [
              {
                input: {
                  security_id: "12346",
                  quantity: 75,
                  stop_loss: 85.0
                },
                reason: "target is missing (required for Super Order)"
              },
              {
                input: {
                  security_id: "12346",
                  quantity: 75,
                  target: 130.75
                },
                reason: "stop_loss is missing (required for Super Order)"
              }
            ]
          }
        }
      end
    end
  end
end
