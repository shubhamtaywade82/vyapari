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
      # @return [Hash] Parsed plan matching schema
      def plan(task:, schema:, context: nil)
        prompt = build_prompt(task, context)
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

      def build_prompt(task, context)
        prompt = <<~PROMPT
          You are a planning engine.
          Output ONLY valid JSON matching the provided schema.
          No explanation. No markdown. No code.

          TASK:
          #{task}
        PROMPT

        prompt += "\nCONTEXT:\n#{JSON.dump(context)}\n" if context

        prompt
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
