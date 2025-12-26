# frozen_string_literal: true

require "technical_analysis" # intrinio/technical-analysis
require "ruby_technical_analysis" # johnnypaper/ruby-technical-analysis

module Vyapari
  module Indicators
    # Unified adapter to use both technical-analysis libraries with Vyapari candle format
    # Uses intrinio/technical-analysis for most indicators
    # Uses ruby-technical-analysis for unique indicators (IMI, Chande Momentum, etc.)
    # Converts candles to the format expected by each library
    class TechnicalAnalysisAdapter
      def initialize(candles)
        @candles = normalize_candles(candles)
        @intrinio_data = convert_to_intrinio_format
        @ruby_ta_data = convert_to_ruby_ta_format
      end

      # ============================================
      # VOLUME-BASED INDICATORS (intrinio/technical-analysis)
      # ============================================

      # On-Balance Volume (OBV) - Cumulative volume indicator
      # Positive OBV suggests buying pressure, negative suggests selling pressure
      def obv(_period: nil)
        return [] if @intrinio_data.empty?

        TechnicalAnalysis::Obv.calculate(@intrinio_data)
      end

      # Chaikin Money Flow (CMF) - Volume-weighted average of accumulation/distribution
      # Range: -1 to +1. Positive = buying pressure, Negative = selling pressure
      def cmf(period: 20)
        return nil if @intrinio_data.length < period

        begin
          # Try with options hash first
          TechnicalAnalysis::Cmf.calculate(@intrinio_data, period: period)
        rescue ArgumentError
          # Fallback: library might expect different format
          nil
        end
      end

      # Money Flow Index (MFI) - Volume-weighted RSI
      # Range: 0-100. >80 = overbought, <20 = oversold
      def mfi(period: 14)
        return nil if @intrinio_data.length < period

        begin
          # Try with options hash first
          TechnicalAnalysis::Mfi.calculate(@intrinio_data, period: period)
        rescue ArgumentError
          # Fallback: library might expect different format
          nil
        end
      end

      # Volume Rate of Change (VROC) - Momentum of volume
      def vroc(period: 12)
        return nil if @intrinio_data.length < period

        begin
          TechnicalAnalysis::Vroc.calculate(@intrinio_data, period: period, volume_key: :volume)
        rescue ArgumentError
          nil
        end
      end

      # Accumulation/Distribution Line (A/D) - Cumulative volume indicator
      def accumulation_distribution
        return [] if @intrinio_data.empty?

        TechnicalAnalysis::Adi.calculate(@intrinio_data)
      end

      # Volume-price Trend (VPT) - Volume-weighted price changes
      def volume_price_trend
        return [] if @intrinio_data.empty?

        TechnicalAnalysis::Vpt.calculate(@intrinio_data, price_key: :close, volume_key: :volume)
      end

      # Volume Weighted Average Price (VWAP)
      def vwap
        return nil if @intrinio_data.empty?

        TechnicalAnalysis::Vwap.calculate(@intrinio_data)
      end

      # Negative Volume Index (NVI) - Tracks price changes on decreasing volume
      def negative_volume_index
        return [] if @intrinio_data.empty?

        TechnicalAnalysis::Nvi.calculate(@intrinio_data, price_key: :close, volume_key: :volume)
      end

      # Force Index (FI) - Combines price change and volume
      def force_index(period: 13)
        return nil if @intrinio_data.length < period

        TechnicalAnalysis::Fi.calculate(@intrinio_data, period: period)
      end

      # Ease of Movement (EOM) - Relationship between price and volume
      def ease_of_movement(period: 14)
        return nil if @intrinio_data.length < period

        TechnicalAnalysis::Eom.calculate(@intrinio_data, period: period)
      end

      # ============================================
      # PRICE-BASED INDICATORS (intrinio/technical-analysis)
      # ============================================

      # RSI - Relative Strength Index
      def rsi(period: 14)
        return nil if @intrinio_data.length < period

        TechnicalAnalysis::Rsi.calculate(@intrinio_data, period: period, price_key: :close)
      end

      # MACD - Moving Average Convergence Divergence
      def macd(fast_period: 12, slow_period: 26, signal_period: 9)
        return nil if @intrinio_data.length < slow_period + signal_period

        TechnicalAnalysis::Macd.calculate(
          @intrinio_data,
          fast_period: fast_period,
          slow_period: slow_period,
          signal_period: signal_period,
          price_key: :close
        )
      end

      # Bollinger Bands
      def bollinger_bands(period: 20, standard_deviations: 2)
        return nil if @intrinio_data.length < period

        TechnicalAnalysis::Bb.calculate(
          @intrinio_data,
          period: period,
          standard_deviations: standard_deviations,
          price_key: :close
        )
      end

      # Stochastic Oscillator
      def stochastic(period: 14, k_period: 3, d_period: 3)
        return nil if @intrinio_data.length < period

        TechnicalAnalysis::Sr.calculate(
          @intrinio_data,
          period: period,
          k_period: k_period,
          d_period: d_period
        )
      end

      # Average True Range (ATR) - Volatility indicator
      def atr(period: 14)
        return nil if @intrinio_data.length < period

        TechnicalAnalysis::Atr.calculate(@intrinio_data, period: period)
      end

      # Average Directional Index (ADX) - Trend strength
      def adx(period: 14)
        return nil if @intrinio_data.length < period * 2

        TechnicalAnalysis::Adx.calculate(@intrinio_data, period: period)
      end

      # Commodity Channel Index (CCI)
      def cci(period: 20)
        return nil if @intrinio_data.length < period

        TechnicalAnalysis::Cci.calculate(@intrinio_data, period: period)
      end

      # Williams %R
      def williams_r(period: 14)
        return nil if @intrinio_data.length < period

        TechnicalAnalysis::Wr.calculate(@intrinio_data, period: period)
      end

      # ============================================
      # UNIQUE INDICATORS (ruby-technical-analysis)
      # ============================================

      # Intraday Momentum Index (IMI) - Only in ruby-technical-analysis
      # Uses open/close series
      def intraday_momentum_index(period: 14)
        return nil if @ruby_ta_data[:oc_series].length < period

        indicator = RubyTechnicalAnalysis::IntradayMomentumIndex.new(
          series: @ruby_ta_data[:oc_series],
          period: period
        )
        indicator.valid? ? indicator.call : nil
      end

      # Chande Momentum Oscillator - Only in ruby-technical-analysis
      def chande_momentum_oscillator(period: 9)
        return nil if @ruby_ta_data[:closes].length < period

        indicator = RubyTechnicalAnalysis::ChandeMomentumOscillator.new(
          series: @ruby_ta_data[:closes],
          period: period
        )
        indicator.valid? ? indicator.call : nil
      end

      # Volume Oscillator - Only in ruby-technical-analysis
      def volume_oscillator(fast_period: 5, slow_period: 10)
        return nil if @ruby_ta_data[:volumes].length < slow_period

        indicator = RubyTechnicalAnalysis::VolumeOscillator.new(
          series: @ruby_ta_data[:volumes],
          fast_period: fast_period,
          slow_period: slow_period
        )
        indicator.valid? ? indicator.call : nil
      end

      # Pivot Points - Only in ruby-technical-analysis
      def pivot_points
        return nil if @ruby_ta_data[:closes].empty?

        # Pivot points typically use high, low, close of previous period
        # This is a simplified version
        last_candle = @candles.last
        high = (last_candle["high"] || last_candle[:high]).to_f
        low = (last_candle["low"] || last_candle[:low]).to_f
        close = (last_candle["close"] || last_candle[:close]).to_f

        pivot = (high + low + close) / 3.0
        {
          pivot: pivot,
          resistance1: (2 * pivot) - low,
          resistance2: pivot + (high - low),
          support1: (2 * pivot) - high,
          support2: pivot - (high - low)
        }
      end

      # ============================================
      # HELPER METHODS - Extract latest values
      # ============================================

      # Get latest indicator value (most recent)
      def latest_obv
        obv_values = obv
        return nil if obv_values.nil? || obv_values.empty?

        # intrinio returns array of objects with .obv attribute
        obv_values.last.respond_to?(:obv) ? obv_values.last.obv : obv_values.last
      end

      def latest_cmf
        cmf_values = cmf
        return nil if cmf_values.nil? || cmf_values.empty?

        # intrinio returns array of objects with .cmf attribute
        cmf_values.last.respond_to?(:cmf) ? cmf_values.last.cmf : cmf_values.last
      end

      def latest_mfi
        mfi_values = mfi
        return nil if mfi_values.nil? || mfi_values.empty?

        # intrinio returns array of objects with .mfi attribute
        mfi_values.last.respond_to?(:mfi) ? mfi_values.last.mfi : mfi_values.last
      end

      def latest_rsi
        rsi_values = rsi
        return nil if rsi_values.nil? || rsi_values.empty?

        # intrinio returns array of objects with .rsi attribute
        rsi_values.last.respond_to?(:rsi) ? rsi_values.last.rsi : rsi_values.last
      end

      def latest_vwap
        vwap_values = vwap
        return nil if vwap_values.nil? || vwap_values.empty?

        vwap_values.last.respond_to?(:vwap) ? vwap_values.last.vwap : vwap_values.last
      end

      def latest_atr
        atr_values = atr
        return nil if atr_values.nil? || atr_values.empty?

        atr_values.last.respond_to?(:atr) ? atr_values.last.atr : atr_values.last
      end

      private

      def normalize_candles(candles_input)
        return [] if candles_input.nil?

        # If already an array, return as-is
        return candles_input if candles_input.is_a?(Array)

        # If string, try to parse as JSON
        if candles_input.is_a?(String)
          begin
            parsed = JSON.parse(candles_input)
            return parsed if parsed.is_a?(Array)
          rescue JSON::ParserError
            # Not JSON, return empty
          end
        end

        # If hash, try to extract array
        return candles_input.values if candles_input.is_a?(Hash) && candles_input.values.first.is_a?(Hash)

        []
      end

      # Convert to intrinio/technical-analysis format (Array of Hashes)
      def convert_to_intrinio_format
        @candles.map do |candle|
          {
            date_time: candle["timestamp"] || candle[:timestamp] || Time.now.to_i,
            open: (candle["open"] || candle[:open] || 0).to_f,
            high: (candle["high"] || candle[:high] || 0).to_f,
            low: (candle["low"] || candle[:low] || 0).to_f,
            close: (candle["close"] || candle[:close] || 0).to_f,
            volume: (candle["volume"] || candle[:volume] || 0).to_f
          }
        end
      end

      # Convert to ruby-technical-analysis format (Arrays of numbers)
      def convert_to_ruby_ta_format
        {
          closes: @candles.map { |c| (c["close"] || c[:close] || 0).to_f },
          opens: @candles.map { |c| (c["open"] || c[:open] || 0).to_f },
          highs: @candles.map { |c| (c["high"] || c[:high] || 0).to_f },
          lows: @candles.map { |c| (c["low"] || c[:low] || 0).to_f },
          volumes: @candles.map { |c| (c["volume"] || c[:volume] || 0).to_f },
          oc_series: @candles.map { |c| [(c["open"] || c[:open] || 0).to_f, (c["close"] || c[:close] || 0).to_f] }
        }
      end
    end
  end
end
