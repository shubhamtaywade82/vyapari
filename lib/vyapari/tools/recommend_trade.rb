# frozen_string_literal: true

module Vyapari
  module Tools
    # Tool for recommending trades
    class RecommendTrade < Base
      def self.name = "recommend_trade"

      def self.schema
        {
          type: "function",
          function: {
            name: name,
            description: "Recommends a trade based on market analysis",
            parameters: {
              type: "object",
              properties: {
                options: { type: "array" },
                trend: { type: "string" }
              },
              required: %w[options trend]
            }
          }
        }
      end

      def call(p)
        return { action: "NO_TRADE" } if p["trend"] == "choppy"

        pp p
        opt = p["options"]
        premium = opt["ltp"].to_f

        {
          action: "BUY",
          security_id: opt["security_id"],
          exchange_segment: opt["exchange_segment"],
          entry_price: premium,
          stop_loss_price: premium * 0.65,
          target_price: premium * 1.4,
          quantity: Trading::Risk.position_size(premium)
        }
      end
    end
  end
end
