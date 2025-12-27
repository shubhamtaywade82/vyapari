# frozen_string_literal: true

module Vyapari
  module Options
    # Tracks daily loss for risk management
    class DailyLossTracker
      DEFAULT_DAILY_LOSS_CAP = 10_000.0 # ₹10,000 default cap

      @daily_losses = {}
      @daily_loss_cap = DEFAULT_DAILY_LOSS_CAP

      class << self
        attr_accessor :daily_loss_cap

        def reset(date = Date.today)
          @daily_losses ||= {}
          @daily_losses[date.to_s] = 0.0
        end

        def add_loss(amount, date = Date.today)
          @daily_losses ||= {}
          @daily_losses[date.to_s] ||= 0.0
          @daily_losses[date.to_s] += amount.to_f
        end

        def current_loss(date = Date.today)
          @daily_losses ||= {}
          @daily_losses[date.to_s] ||= 0.0
        end

        def remaining(date = Date.today)
          current = current_loss(date)
          cap = @daily_loss_cap || DEFAULT_DAILY_LOSS_CAP
          [cap - current, 0.0].max
        end

        def can_trade?(max_loss_per_trade, date = Date.today)
          remaining(date) >= max_loss_per_trade
        end
      end
    end
  end
end
