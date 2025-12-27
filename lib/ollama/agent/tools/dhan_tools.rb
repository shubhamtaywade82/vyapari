# frozen_string_literal: true

require_relative "../tool_registry"

module Ollama
  class Agent
    module Tools
      # DhanHQ trading tools - examples of formal tool descriptors
      class DhanTools
        def self.register_all(registry:, dhan_client: nil)
          # Tool 1: Fetch Live Trading Price
          registry.register(
            descriptor: {
              name: "dhan.fetch_ltp",
              description: "Fetches live LTP (Last Traded Price) for an instrument from DhanHQ",
              when_to_use: "When current market price is required for analysis or order placement",
              when_not_to_use: "If price is already cached in context and still valid",
              inputs: {
                type: "object",
                properties: {
                  security_id: {
                    type: "string",
                    description: "DhanHQ security ID for the instrument"
                  }
                },
                required: ["security_id"]
              },
              outputs: {
                type: "object",
                properties: {
                  ltp: { type: "number", description: "Last traded price" },
                  timestamp: { type: "string", description: "Price timestamp" }
                }
              },
              side_effects: ["Read-only operation - no market impact"],
              safety_rules: []
            },
            handler: ->(args) {
              if dhan_client
                dhan_client.ltp(args[:security_id] || args["security_id"])
              else
                { ltp: 0, timestamp: Time.now.iso8601, error: "DhanHQ client not configured" }
              end
            }
          )

          # Tool 2: Place Order (DRY-RUN SAFE)
          registry.register(
            descriptor: {
              name: "dhan.place_order",
              description: "Places an options BUY order on DhanHQ exchange",
              when_to_use: "Only after trade decision is finalized, risk validated, and stoploss is set",
              when_not_to_use: "During analysis, planning, or when uncertain about trade direction",
              inputs: {
                type: "object",
                properties: {
                  symbol: {
                    type: "string",
                    description: "Option symbol (e.g., 'NIFTY25JAN24500CE')"
                  },
                  exchange: {
                    type: "string",
                    enum: ["NFO"],
                    description: "Exchange segment"
                  },
                  transaction_type: {
                    type: "string",
                    enum: ["BUY"],
                    description: "Transaction type"
                  },
                  quantity: {
                    type: "integer",
                    minimum: 1,
                    description: "Number of lots"
                  },
                  order_type: {
                    type: "string",
                    enum: ["MARKET", "LIMIT"],
                    description: "Order type"
                  },
                  price: {
                    type: "number",
                    nullable: true,
                    description: "Limit price (required for LIMIT orders)"
                  }
                },
                required: ["symbol", "exchange", "transaction_type", "quantity", "order_type"]
              },
              outputs: {
                type: "object",
                properties: {
                  order_id: { type: "string", description: "Order ID from exchange" },
                  status: { type: "string", description: "Order status" }
                }
              },
              side_effects: [
                "Places a REAL order if not in dry-run mode",
                "Deducts margin from account",
                "Creates market exposure"
              ],
              safety_rules: [
                "Never place order without stoploss planned",
                "Never exceed max position size",
                "Never place order during market closure"
              ]
            },
            handler: ->(args) {
              if ENV["DRY_RUN"] == "true" || ENV["DRY_RUN_MODE"] == "true"
                {
                  order_id: "SIMULATED_#{Time.now.to_i}",
                  status: "DRY_RUN",
                  message: "Order simulated - dry-run mode active"
                }
              elsif dhan_client
                dhan_client.place_order(
                  symbol: args[:symbol] || args["symbol"],
                  exchange: args[:exchange] || args["exchange"],
                  transaction_type: args[:transaction_type] || args["transaction_type"],
                  quantity: args[:quantity] || args["quantity"],
                  order_type: args[:order_type] || args["order_type"],
                  price: args[:price] || args["price"]
                )
              else
                {
                  order_id: nil,
                  status: "error",
                  error: "DhanHQ client not configured"
                }
              end
            }
          )

          # Tool 3: Fetch Option Chain
          registry.register(
            descriptor: {
              name: "dhan.fetch_option_chain",
              description: "Fetches option chain data for an underlying instrument",
              when_to_use: "When analyzing option strikes, premiums, and Greeks",
              when_not_to_use: "If option chain is already cached and market hasn't moved significantly",
              inputs: {
                type: "object",
                properties: {
                  symbol: {
                    type: "string",
                    description: "Underlying symbol (e.g., 'NIFTY', 'BANKNIFTY')"
                  },
                  expiry: {
                    type: "string",
                    description: "Expiry date (YYYY-MM-DD format)"
                  }
                },
                required: ["symbol", "expiry"]
              },
              outputs: {
                type: "object",
                properties: {
                  contracts: {
                    type: "array",
                    description: "Array of option contracts with strikes, premiums, Greeks"
                  },
                  spot_price: { type: "number", description: "Current spot price" }
                }
              },
              side_effects: ["Read-only operation - no market impact"],
              safety_rules: []
            },
            handler: ->(args) {
              if dhan_client
                dhan_client.fetch_option_chain(
                  symbol: args[:symbol] || args["symbol"],
                  expiry: args[:expiry] || args["expiry"]
                )
              else
                {
                  contracts: [],
                  spot_price: 0,
                  error: "DhanHQ client not configured"
                }
              end
            }
          )

          # Tool 4: Get Positions
          registry.register(
            descriptor: {
              name: "dhan.get_positions",
              description: "Fetches current open positions from DhanHQ",
              when_to_use: "When checking current exposure, calculating risk, or before placing new orders",
              when_not_to_use: "If position data is already cached and recent",
              inputs: {
                type: "object",
                properties: {},
                required: []
              },
              outputs: {
                type: "object",
                properties: {
                  positions: {
                    type: "array",
                    description: "Array of open positions"
                  },
                  total_exposure: { type: "number", description: "Total position value" }
                }
              },
              side_effects: ["Read-only operation - no market impact"],
              safety_rules: []
            },
            handler: ->(_args) {
              if dhan_client
                dhan_client.get_positions
              else
                {
                  positions: [],
                  total_exposure: 0,
                  error: "DhanHQ client not configured"
                }
              end
            }
          )
        end
      end
    end
  end
end

