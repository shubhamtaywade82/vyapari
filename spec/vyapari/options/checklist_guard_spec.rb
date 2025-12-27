# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/vyapari/options/checklist_guard"

RSpec.describe Vyapari::Options::ChecklistGuard do
  let(:guard) { described_class.new }
  let(:config_path) { File.join(__dir__, "../../../lib/vyapari/options/checklist_config.yml") }

  describe "#initialize" do
    it "loads configuration from YAML file" do
      expect(guard.config).to be_a(Hash)
      expect(guard.config).to have_key("global_precheck")
      expect(guard.config).to have_key("phase_1_agent_a")
      expect(guard.config).to have_key("phase_2_agent_b")
    end
  end

  describe "#run_global_precheck" do
    context "when all checks pass" do
      let(:context) do
        {
          market_open: true,
          no_event_risk: true,
          websocket_connected: true,
          dhan_authenticated: true,
          in_cooldown: false,
          duplicate_position: false
        }
      end

      it "returns passed: true" do
        result = guard.run_global_precheck(context: context)
        expect(result[:passed]).to be true
        expect(result[:failures]).to be_empty
      end
    end

    context "when market is closed" do
      let(:context) do
        {
          market_open: false,
          websocket_connected: true,
          dhan_authenticated: true
        }
      end

      it "returns passed: false with STOP_SYSTEM action" do
        result = guard.run_global_precheck(context: context)
        expect(result[:passed]).to be false
        expect(result[:action]).to eq("STOP_SYSTEM")
        expect(result[:failures]).not_to be_empty
      end
    end

    context "when websocket is disconnected" do
      let(:context) do
        {
          market_open: true,
          websocket_connected: false,
          dhan_authenticated: true
        }
      end

      it "returns passed: false" do
        result = guard.run_global_precheck(context: context)
        expect(result[:passed]).to be false
        expect(result[:action]).to eq("STOP_SYSTEM")
      end
    end
  end

  describe "#run_phase_1_checks" do
    context "OPTIONS_INTRADAY mode" do
      let(:trade_plan) do
        {
          mode: "OPTIONS_INTRADAY",
          regime: "TREND",
          direction: "BULLISH",
          momentum: "STRONG",
          alignment_with_htf: true,
          entry_trigger: "BREAKOUT",
          strike_candidates: [{ strike: 22500 }],
          stop_loss_logic: "1m candle close below last higher low",
          take_profit_logic: "15m range high + expansion",
          invalidation_rules: ["15m closes inside range"]
        }
      end

      let(:context) do
        {
          regime: "TREND",
          direction: "BULLISH",
          momentum: "STRONG"
        }
      end

      it "passes when all checks are met" do
        result = guard.run_phase_1_checks(mode: "OPTIONS_INTRADAY", trade_plan: trade_plan, context: context)
        expect(result[:passed]).to be true
        expect(result[:failures]).to be_empty
      end

      it "fails when regime is RANGE" do
        trade_plan[:regime] = "RANGE"
        context[:regime] = "RANGE"

        result = guard.run_phase_1_checks(mode: "OPTIONS_INTRADAY", trade_plan: trade_plan, context: context)
        expect(result[:passed]).to be false
        expect(result[:action]).to eq("NO_TRADE")
      end

      it "fails when direction doesn't align with HTF" do
        context[:alignment_with_htf] = false

        result = guard.run_phase_1_checks(mode: "OPTIONS_INTRADAY", trade_plan: trade_plan, context: context)
        expect(result[:passed]).to be false
        expect(result[:action]).to eq("NO_TRADE")
      end

      it "fails when required outputs are missing" do
        trade_plan.delete(:stop_loss_logic)

        result = guard.run_phase_1_checks(mode: "OPTIONS_INTRADAY", trade_plan: trade_plan, context: context)
        expect(result[:passed]).to be false
        expect(result[:failures].any? { |f| f[:description].include?("Missing required outputs") }).to be true
      end
    end

    context "SWING_LONG mode" do
      let(:trade_plan) do
        {
          mode: "SWING_LONG",
          trend: "UP",
          structure: "HH_HL",
          setup_type: "PULLBACK",
          entry_zone: "Near support at 150",
          stop_loss_logic: "Below swing low",
          take_profit_logic: "Previous day high"
        }
      end

      let(:context) do
        {
          trend: "UP",
          structure: "HH_HL"
        }
      end

      it "passes when all checks are met" do
        result = guard.run_phase_1_checks(mode: "SWING_LONG", trade_plan: trade_plan, context: context)
        expect(result[:passed]).to be true
      end

      it "fails when trend is SIDEWAYS" do
        trade_plan[:trend] = "SIDEWAYS"
        context[:trend] = "SIDEWAYS"

        result = guard.run_phase_1_checks(mode: "SWING_LONG", trade_plan: trade_plan, context: context)
        expect(result[:passed]).to be false
      end
    end

    context "invalid mode" do
      it "fails for invalid mode" do
        result = guard.run_phase_1_checks(mode: "INVALID_MODE", trade_plan: {}, context: {})
        expect(result[:passed]).to be false
        expect(result[:action]).to eq("STOP")
      end
    end
  end

  describe "#run_phase_2_checks" do
    let(:executable_plan) do
      {
        quantity: 75,
        lots: 1,
        entry_price: 95.25,
        stop_loss: 85.00,
        take_profit: {
          partial: { price: 110.50, rr: 1.2, exit_pct: 50 },
          final: { price: 130.75, rr: 2.0, exit_pct: 50 }
        },
        order_type: "SUPER",
        security_id: "12346",
        total_risk: 768.75
      }
    end

    let(:context) do
      {
        instrument: "NIFTY",
        lot_size: 75,
        funds_available: 85000
      }
    end

    it "passes when all validations pass" do
      result = guard.run_phase_2_checks(executable_plan: executable_plan, context: context)
      expect(result[:passed]).to be true
      expect(result[:failures]).to be_empty
    end

    it "fails when SL exceeds max percentage" do
      executable_plan[:stop_loss] = 50.00 # 47.5% SL

      result = guard.run_phase_2_checks(executable_plan: executable_plan, context: context)
      expect(result[:passed]).to be false
      expect(result[:action]).to eq("REJECT")
      expect(result[:failures].any? { |f| f[:description].include?("exceeds max") }).to be true
    end

    it "fails when lots < 1" do
      executable_plan[:lots] = 0
      executable_plan[:quantity] = 0

      result = guard.run_phase_2_checks(executable_plan: executable_plan, context: context)
      expect(result[:passed]).to be false
      expect(result[:failures].any? { |f| f[:description].include?("Lots must be >= 1") }).to be true
    end

    it "fails when lots exceed max" do
      executable_plan[:lots] = 10
      executable_plan[:quantity] = 750

      result = guard.run_phase_2_checks(executable_plan: executable_plan, context: context)
      expect(result[:passed]).to be false
      expect(result[:failures].any? { |f| f[:description].include?("exceeds max") }).to be true
    end

    it "fails when quantity doesn't match lots × lot_size" do
      executable_plan[:quantity] = 100 # Should be 75 for 1 lot

      result = guard.run_phase_2_checks(executable_plan: executable_plan, context: context)
      expect(result[:passed]).to be false
      expect(result[:failures].any? { |f| f[:description].include?("does not match") }).to be true
    end

    it "fails when required fields are missing" do
      executable_plan.delete(:stop_loss)

      result = guard.run_phase_2_checks(executable_plan: executable_plan, context: context)
      expect(result[:passed]).to be false
      expect(result[:failures].any? { |f| f[:description].include?("Required field missing") }).to be true
    end
  end

  describe "#run_phase_3_checks" do
    context "when all pre-execution checks pass" do
      let(:execution_context) do
        {
          trade_approved: true,
          duplicate_order: false,
          order_type_allowed: true,
          dry_run_enabled: false
        }
      end

      it "returns passed: true" do
        result = guard.run_phase_3_checks(execution_context: execution_context)
        expect(result[:passed]).to be true
      end
    end

    context "when trade is not approved" do
      let(:execution_context) do
        {
          trade_approved: false
        }
      end

      it "returns passed: false" do
        result = guard.run_phase_3_checks(execution_context: execution_context)
        expect(result[:passed]).to be false
        expect(result[:action]).to eq("STOP_AND_ALERT")
      end
    end

    context "when duplicate order exists" do
      let(:execution_context) do
        {
          trade_approved: true,
          duplicate_order: true
        }
      end

      it "returns passed: false" do
        result = guard.run_phase_3_checks(execution_context: execution_context)
        expect(result[:passed]).to be false
      end
    end
  end

  describe "#check_system_kill_conditions" do
    context "when max daily loss is breached" do
      let(:system_state) do
        {
          daily_loss: 5000,
          max_daily_loss: 3000
        }
      end

      it "returns should_halt: true" do
        result = guard.check_system_kill_conditions(system_state: system_state)
        expect(result[:should_halt]).to be true
        expect(result[:reason]).to include("Max daily loss")
      end
    end

    context "when WS disconnected mid-position" do
      let(:system_state) do
        {
          websocket_connected: false,
          has_position: true
        }
      end

      it "returns should_halt: true" do
        result = guard.check_system_kill_conditions(system_state: system_state)
        expect(result[:should_halt]).to be true
        expect(result[:reason]).to include("WS disconnected")
      end
    end

    context "when duplicate execution detected" do
      let(:system_state) do
        {
          duplicate_execution: true
        }
      end

      it "returns should_halt: true" do
        result = guard.check_system_kill_conditions(system_state: system_state)
        expect(result[:should_halt]).to be true
      end
    end

    context "when no kill conditions are met" do
      let(:system_state) do
        {
          daily_loss: 1000,
          max_daily_loss: 3000,
          websocket_connected: true,
          has_position: false
        }
      end

      it "returns should_halt: false" do
        result = guard.check_system_kill_conditions(system_state: system_state)
        expect(result[:should_halt]).to be false
      end
    end
  end
end

