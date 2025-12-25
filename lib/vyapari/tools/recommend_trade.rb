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
            description: "STEP 6: Final step - Recommends a trade based on market analysis. MUST be called last. ALL parameters (options, trend) are automatically injected from context - call with empty parameters: {}. Returns NO_TRADE if trend is 'avoid' or 'choppy'.",
            parameters: {
              type: "object",
              properties: {},
              required: []
            }
          }
        }
      end

      def call(p)
        trend = p["trend"] || p[:trend]
        if %w[avoid choppy].include?(trend.to_s.downcase)
          return { action: "NO_TRADE",
                   reason: "Market trend is 'avoid' - choppy market conditions" }
        end

        # Extract options - can be hash (from fetch_option_chain) or array (from LLM)
        opt = p["options"] || p[:options]

        # Handle hash format from fetch_option_chain (has contracts array)
        if opt.is_a?(Hash)
          contracts = opt["contracts"] || opt[:contracts] || []
          raise "No contracts available in options" if contracts.empty?

          # Use first contract for entry
          contract = contracts.first
          premium = (contract["last_price"] || contract[:last_price] ||
                     contract["average_price"] || contract[:average_price] || 0).to_f

          raise "Invalid premium: #{premium}" if premium.zero?

          security_id = contract["security_id"] || contract[:security_id]
          side = (opt["side"] || opt[:side] || "CE").to_s.upcase
        elsif opt.is_a?(Array) && !opt.empty?
          # Handle array format (direct contracts)
          contract = opt.first
          premium = (contract["last_price"] || contract[:last_price] ||
                     contract["average_price"] || contract[:average_price] || 0).to_f

          raise "Invalid premium: #{premium}" if premium.zero?

          security_id = contract["security_id"] || contract[:security_id]
          side = "CE" # Default, should come from context
        else
          raise "Invalid options format: expected hash with contracts or array of contracts"
        end

        # Calculate position size (prevent division by zero)
        quantity = Trading::Risk.position_size(premium)

        {
          action: "BUY",
          side: side,
          security_id: security_id,
          entry_price: premium,
          stop_loss_price: premium * 0.65,
          target_price: premium * 1.4,
          quantity: quantity
        }
      end
    end
  end
end
