# frozen_string_literal: true

require "json"

module Ollama
  # Planning engine that uses Ollama to generate structured plans
  # Uses /api/generate with JSON schema for deterministic output
  class Agent
    class Planner
      def initialize(client:, model:, temperature: 0.2)
        @client = client
        @model = model
        @temperature = temperature
      end

      # Generate a plan from a task description
      # @param task [String] Task description
      # @param schema [Hash] JSON schema for plan structure
      # @param context [Hash, nil] Additional context to include
      # @param tool_descriptors [Array<Hash>, nil] Tool descriptors for prompt
      # @return [Hash] Parsed plan matching schema
      def plan(task:, schema:, context: nil, tool_descriptors: nil)
        prompt = build_prompt(task, context, tool_descriptors)
        options = { temperature: @temperature }

        response = @client.generate(
          model: @model,
          prompt: prompt,
          format: schema,
          stream: false,
          options: options
        )

        parse_response(response)
      rescue JSON::ParserError => e
        raise PlannerError, "Invalid planner output: #{e.message}"
      end

      private

      def build_prompt(task, context, tool_descriptors)
        prompt = <<~PROMPT
          You are an execution planner.

          RULES:
          - You MUST choose tools only when necessary
          - Never hallucinate tool outputs
          - Never invent arguments
          - Return tool calls in JSON only
          - Follow tool schemas exactly

          #{tool_descriptors ? build_tools_section(tool_descriptors) : ""}

          TASK:
          #{task}
        PROMPT

        prompt += "\nCONTEXT:\n#{JSON.dump(context)}\n" if context

        prompt += <<~PROMPT

          You must output one of:
          1. A tool call (action: "tool_call", tool_name: "...", tool_args: {...})
          2. A final answer (action: "final", final_output: "...")

          Output ONLY valid JSON matching the provided schema.
          No explanation. No markdown. No code.
        PROMPT

        prompt
      end

      def build_tools_section(tool_descriptors)
        require "json"
        tools_json = JSON.pretty_generate(tool_descriptors)

        <<~TOOLS
          AVAILABLE TOOLS:
          Each tool has a strict input/output schema.
          You MUST use tools exactly as described.

          #{tools_json}
        TOOLS
      end

      def parse_response(response)
        content = response["response"] || response["message"]&.dig("content")
        raise PlannerError, "Empty response from model" unless content

        # Try to extract JSON if wrapped in markdown
        json_match = content.match(/\{[\s\S]*\}/)
        json_str = json_match ? json_match[0] : content

        JSON.parse(json_str)
      end
    end

    class PlannerError < StandardError; end
  end
end
