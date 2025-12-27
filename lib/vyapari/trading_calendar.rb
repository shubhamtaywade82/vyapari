# frozen_string_literal: true

require "date"

module Vyapari
  # Trading calendar service for resolving trading days
  # Controller-owned, not LLM-owned
  class TradingCalendar
    # Indian market holidays (2025)
    # TODO: Replace with NSE holiday API or YAML config
    TRADING_HOLIDAYS_2025 = [
      Date.parse("2025-01-26"), # Republic Day
      Date.parse("2025-03-08"), # Holi
      Date.parse("2025-03-29"), # Good Friday
      Date.parse("2025-04-14"), # Ambedkar Jayanti
      Date.parse("2025-04-17"), # Ram Navami
      Date.parse("2025-05-01"), # Labour Day
      Date.parse("2025-06-17"), # Id-ul-Fitr
      Date.parse("2025-08-15"), # Independence Day
      Date.parse("2025-08-26"), # Janmashtami
      Date.parse("2025-10-02"), # Gandhi Jayanti
      Date.parse("2025-10-12"), # Dussehra
      Date.parse("2025-10-31"), # Diwali Balipratipada
      Date.parse("2025-11-01"), # Diwali
      Date.parse("2025-11-15"), # Guru Nanak Jayanti
      Date.parse("2025-12-25")  # Christmas
    ].freeze

    # Indian market holidays (2026)
    # TODO: Replace with NSE holiday API or YAML config
    TRADING_HOLIDAYS_2026 = [
      Date.parse("2026-01-26"), # Republic Day
      Date.parse("2026-03-14"), # Holi
      Date.parse("2026-03-28"), # Good Friday
      Date.parse("2026-04-14"), # Ambedkar Jayanti
      Date.parse("2026-04-03"), # Ram Navami
      Date.parse("2026-05-01"), # Labour Day
      Date.parse("2026-06-06"), # Id-ul-Fitr
      Date.parse("2026-08-15"), # Independence Day
      Date.parse("2026-08-14"), # Janmashtami
      Date.parse("2026-10-02"), # Gandhi Jayanti
      Date.parse("2026-10-01"), # Dussehra
      Date.parse("2026-10-20"), # Diwali Balipratipada
      Date.parse("2026-10-21"), # Diwali
      Date.parse("2026-11-04"), # Guru Nanak Jayanti
      Date.parse("2026-12-25")  # Christmas
    ].freeze

    # Check if a date is a trading day
    # @param date [Date] Date to check
    # @return [Boolean] true if trading day, false otherwise
    def self.trading_day?(date)
      date = date.to_date if date.respond_to?(:to_date)
      !(date.saturday? || date.sunday? || trading_holiday?(date))
    end

    # Check if a date is a trading holiday
    # @param date [Date] Date to check
    # @return [Boolean] true if holiday, false otherwise
    def self.trading_holiday?(date)
      date = date.to_date if date.respond_to?(:to_date)
      year = date.year
      holidays = case year
                 when 2025
                   TRADING_HOLIDAYS_2025
                 when 2026
                   TRADING_HOLIDAYS_2026
                 else
                   [] # Unknown year - assume no holidays (can be extended)
                 end
      holidays.include?(date)
    end

    # Get the last trading day before a given date
    # @param date [Date] Reference date
    # @return [Date] Last trading day before date
    def self.last_trading_day(date)
      date = date.to_date if date.respond_to?(:to_date)
      d = date - 1
      d -= 1 until trading_day?(d)
      d
    end

    # Get the next trading day after a given date
    # @param date [Date] Reference date
    # @return [Date] Next trading day after date
    def self.next_trading_day(date)
      date = date.to_date if date.respond_to?(:to_date)
      d = date + 1
      d += 1 until trading_day?(d)
      d
    end

    # Resolve LIVE mode dates (to_date = today, from_date = last trading day)
    # @param today [Date] Today's date (defaults to Date.current)
    # @return [Hash] { to_date: String, from_date: String, from_date_reason: String }
    def self.resolve_live_dates(today = Date.current)
      to_date = today
      from_date = last_trading_day(today)

      {
        to_date: to_date.to_s,
        from_date: from_date.to_s,
        from_date_reason: "LAST_TRADING_DAY"
      }
    end

    # Validate that a date is a trading day
    # @param date [Date, String] Date to validate
    # @return [Hash] { valid: Boolean, error: String }
    def self.validate_trading_day(date)
      date = Date.parse(date.to_s) if date.is_a?(String)
      if trading_day?(date)
        { valid: true, error: nil }
      else
        reason = if date.saturday?
                   "Saturday"
                 elsif date.sunday?
                   "Sunday"
                 elsif trading_holiday?(date)
                   "Trading holiday"
                 else
                   "Non-trading day"
                 end
        { valid: false, error: "#{date} is a #{reason} and not a trading day" }
      end
    end
  end
end
