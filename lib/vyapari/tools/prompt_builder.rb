# frozen_string_literal: true

require "json"
require_relative "enhanced_dhan_tools"

# Builds system prompts with tool descriptors for Ollama
module Vyapari
  module Tools
    class PromptBuilder
      SYSTEM_PROMPT_TEMPLATE = <<~PROMPT
        You are an execution planner for options trading.

        You have access to the following tools.
        Each tool has:
        - strict input and output schemas
        - usage constraints (when_to_use / when_not_to_use)
        - safety rules
        - real-world side effects

        RULES:
        - Use tools ONLY when required
        - Never invent tool arguments
        - Never assume tool success
        - Prefer Super Orders (dhan.super.place) for options buying
        - Never place order without stop-loss
        - If unsure, return NO_ACTION
        - Follow examples exactly (valid examples show correct usage)
        - Avoid invalid examples (they show common mistakes)

        TOOLS:
        {{TOOLS_JSON}}

        You must respond with ONE of:
        1. A tool_call matching a tool schema exactly
        2. A final JSON answer (NO_ACTION or explanation)

        OUTPUT SCHEMA:
        {
          "action": "tool_call | final",
          "tool_name": "string (if action=tool_call)",
          "tool_args": "object (if action=tool_call)",
          "final_output": "string (if action=final)"
        }
      PROMPT

      def self.build_system_prompt(tools: nil, mode: :options_intraday)
        tools ||= EnhancedDhanTools.all

        # Filter tools by mode if needed
        tools = filter_tools_by_mode(tools, mode) if mode

        tools_json = JSON.pretty_generate(tools)

        SYSTEM_PROMPT_TEMPLATE.gsub("{{TOOLS_JSON}}", tools_json)
      end

      def self.filter_tools_by_mode(tools, mode)
        case mode
        when :options_intraday
          # Include all tools for options intraday
          tools
        when :swing_long
          # Exclude option-specific tools
          tools.reject { |t| t[:name].start_with?("dhan.option.") }
        else
          tools
        end
      end

      def self.build_planner_output_schema
        {
          type: "object",
          properties: {
            action: {
              type: "string",
              enum: ["tool_call", "final"]
            },
            tool_name: {
              type: "string",
              description: "Tool name (required if action=tool_call)"
            },
            tool_args: {
              type: "object",
              description: "Tool arguments (required if action=tool_call)",
              additionalProperties: true
            },
            final_output: {
              type: "string",
              description: "Final answer or NO_ACTION (required if action=final)"
            }
          },
          required: ["action"]
        }
      end

      # Get tools as JSON string for injection
      def self.tools_json(tools: nil)
        tools ||= EnhancedDhanTools.all
        JSON.pretty_generate(tools)
      end

      # Get tools formatted for Ollama /api/generate format parameter
      def self.tools_for_ollama_format(tools: nil)
        tools ||= EnhancedDhanTools.all

        # Convert to format suitable for Ollama's format parameter
        tools.map do |tool|
          {
            name: tool[:name],
            description: tool[:description],
            inputs: tool[:inputs],
            outputs: tool[:outputs],
            examples: tool[:examples]
          }
        end
      end
    end
  end
end

