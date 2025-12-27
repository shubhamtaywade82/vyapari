# frozen_string_literal: true

require "spec_helper"
require "json"
require "json-schema"
require_relative "../../../lib/vyapari/tools/enhanced_dhan_tools"

RSpec.describe "ToolDescriptor Schema Validation" do
  let(:schema_path) { File.join(__dir__, "../../../schemas/tool_descriptor.schema.json") }
  let(:schema) { JSON.parse(File.read(schema_path)) }

  describe "ToolDescriptor JSON Schema" do
    it "validates schema file exists" do
      expect(File.exist?(schema_path)).to be true
    end

    it "validates schema is valid JSON Schema" do
      expect { JSON::Validator.validate!(schema, {}) }.not_to raise_error
    end
  end

  describe "Enhanced DhanHQ Tools" do
    let(:all_tools) { Vyapari::Tools::EnhancedDhanTools.all }

    it "returns array of tool descriptors" do
      expect(all_tools).to be_an(Array)
      expect(all_tools.length).to be > 0
    end

    describe "each tool descriptor" do
      all_tools.each do |tool|
        context "tool: #{tool[:name]}" do
          it "validates against ToolDescriptor schema" do
            errors = JSON::Validator.fully_validate(schema, tool)
            expect(errors).to be_empty, "Tool #{tool[:name]} failed validation: #{errors.join(', ')}"
          end

          it "has required fields" do
            expect(tool).to have_key(:name)
            expect(tool).to have_key(:category)
            expect(tool).to have_key(:description)
            expect(tool).to have_key(:purpose)
            expect(tool).to have_key(:when_to_use)
            expect(tool).to have_key(:when_not_to_use)
            expect(tool).to have_key(:inputs)
            expect(tool).to have_key(:outputs)
            expect(tool).to have_key(:side_effects)
            expect(tool).to have_key(:safety_rules)
            expect(tool).to have_key(:examples)
          end

          it "has valid name format" do
            expect(tool[:name]).to match(/^[a-z0-9_.]+$/)
          end

          it "has non-empty when_to_use array" do
            expect(tool[:when_to_use]).to be_an(Array)
            expect(tool[:when_to_use].length).to be > 0
          end

          it "has examples with valid and invalid arrays" do
            expect(tool[:examples]).to have_key(:valid)
            expect(tool[:examples]).to have_key(:invalid)
            expect(tool[:examples][:valid]).to be_an(Array)
            expect(tool[:examples][:invalid]).to be_an(Array)
          end

          it "has valid examples with required fields" do
            tool[:examples][:valid].each do |example|
              expect(example).to have_key(:input)
              expect(example).to have_key(:comment)
              expect(example[:input]).to be_a(Hash)
              expect(example[:comment]).to be_a(String)
            end
          end

          it "has invalid examples with required fields" do
            tool[:examples][:invalid].each do |example|
              expect(example).to have_key(:input)
              expect(example).to have_key(:reason)
              expect(example[:input]).to be_a(Hash)
              expect(example[:reason]).to be_a(String)
            end
          end

          it "has inputs as JSON Schema object" do
            expect(tool[:inputs]).to be_a(Hash)
            expect(tool[:inputs]).to have_key(:type)
            expect(tool[:inputs][:type]).to eq("object")
          end

          it "has outputs as JSON Schema object" do
            expect(tool[:outputs]).to be_a(Hash)
            expect(tool[:outputs]).to have_key(:type)
            expect(tool[:outputs][:type]).to eq("object")
          end

          it "has side_effects as array" do
            expect(tool[:side_effects]).to be_an(Array)
          end

          it "has safety_rules as array" do
            expect(tool[:safety_rules]).to be_an(Array)
          end
        end
      end
    end
  end

  describe "Specific tool validations" do
    describe "dhan.order.place" do
      let(:tool) { Vyapari::Tools::EnhancedDhanTools.place_order }

      it "has dry_run_behavior defined" do
        expect(tool).to have_key(:dry_run_behavior)
        expect(tool[:dry_run_behavior][:enabled]).to be true
      end

      it "has defaults defined" do
        expect(tool).to have_key(:defaults)
        expect(tool[:defaults][:order_type]).to eq("MARKET")
      end

      it "has safety rules about lot size" do
        safety_rules = tool[:safety_rules].join(" ")
        expect(safety_rules).to include("lot size")
      end
    end

    describe "dhan.super.place" do
      let(:tool) { Vyapari::Tools::EnhancedDhanTools.super_place }

      it "requires stop_loss in inputs" do
        required = tool[:inputs][:required] || []
        expect(required).to include("stop_loss")
      end

      it "requires target in inputs" do
        required = tool[:inputs][:required] || []
        expect(required).to include("target")
      end

      it "has safety rules about SL/TP" do
        safety_rules = tool[:safety_rules].join(" ")
        expect(safety_rules).to include("MANDATORY")
      end
    end

    describe "dhan.option.chain" do
      let(:tool) { Vyapari::Tools::EnhancedDhanTools.option_chain }

      it "has safety rules about strike selection" do
        safety_rules = tool[:safety_rules].join(" ")
        expect(safety_rules).to include("ATM")
      end
    end
  end

  describe "Tool injection into Ollama" do
    it "can serialize all tools to JSON" do
      tools_json = JSON.pretty_generate(Vyapari::Tools::EnhancedDhanTools.all)
      expect(tools_json).to be_a(String)
      expect { JSON.parse(tools_json) }.not_to raise_error
    end

    it "can build system prompt with tools" do
      tools = Vyapari::Tools::EnhancedDhanTools.all
      tools_json = JSON.pretty_generate(tools)

      prompt = <<~PROMPT
        You are an execution planner.

        You have access to the following tools:
        #{tools_json}

        RULES:
        - Use tools ONLY when required
        - Never invent tool arguments
        - Prefer Super Orders for options buying
        - Never place order without stop-loss
      PROMPT

      expect(prompt).to include("dhan.order.place")
      expect(prompt).to include("dhan.super.place")
    end
  end
end

