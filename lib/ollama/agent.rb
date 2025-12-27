# frozen_string_literal: true

require_relative "client"

module Ollama
  # High-level agent orchestration
  # Combines planner, executor, verifier, and loop into a single interface
  class Agent
    DEFAULT_MODEL = "mistral"
    DEFAULT_PLAN_SCHEMA = {
      "type" => "object",
      "properties" => {
        "steps" => {
          "type" => "array",
          "items" => {
            "type" => "object",
            "properties" => {
              "tool" => { "type" => "string" },
              "args" => { "type" => "object" }
            },
            "required" => %w[tool args]
          }
        },
        "stop_reason" => { "type" => "string" }
      },
      "required" => ["steps"]
    }.freeze

    def initialize(client: nil, model: DEFAULT_MODEL, tools: {}, max_iterations: 3, timeout: 30)
      @client = client || Client.new
      @model = model
      @tools = tools
      @max_iterations = max_iterations
      @timeout = timeout

      # Lazy load agent components to avoid namespace conflicts
      load_agent_components

      @planner = Agent::Planner.new(client: @client, model: @model)
      @executor = Agent::Executor.new(tools: @tools)
      @verifier = Agent::Verifier.new(schema: DEFAULT_PLAN_SCHEMA)
      @loop = Agent::Loop.new(
        planner: @planner,
        executor: @executor,
        verifier: @verifier,
        max_iterations: @max_iterations,
        timeout: @timeout
      )
    end

    # Generate a plan for a task
    # @param task [String] Task description
    # @param schema [Hash, nil] Custom plan schema (uses default if nil)
    # @param context [Hash, nil] Additional context
    # @return [Hash] Generated plan
    def plan(task:, schema: nil, context: nil)
      plan_schema = schema || DEFAULT_PLAN_SCHEMA
      @planner.plan(task: task, schema: plan_schema, context: context)
    end

    # Execute a single tool call
    # @param tool_name [String] Tool to execute
    # @param args [Hash] Tool arguments
    # @return [Hash] Execution result
    def execute(tool_name:, args: {})
      @executor.execute(tool_name: tool_name, args: args)
    end

    # Verify a plan or result
    # @param data [Hash] Plan or result to verify
    # @return [Hash] Verification result
    def verify(data)
      if data.key?("steps") || data.key?(:steps)
        @verifier.verify_plan(data)
      else
        @verifier.verify_result(data)
      end
    end

    # Run the full agent loop
    # @param task [String] Initial task
    # @param plan_schema [Hash, nil] Custom plan schema
    # @return [Hash] Final result with context and trace
    def loop(task:, plan_schema: nil)
      schema = plan_schema || DEFAULT_PLAN_SCHEMA
      @loop.run(task: task, plan_schema: schema)
    end

    # Generate final output/summary from context
    # @param context [Array<Hash>] Execution context
    # @param prompt [String, nil] Custom prompt (uses default if nil)
    # @param format [Hash, nil] Output schema
    # @return [Hash] Final generated output
    def finalize(context:, prompt: nil, format: nil)
      final_prompt = prompt || build_default_final_prompt(context)

      response = @client.generate(
        model: @model,
        prompt: final_prompt,
        format: format,
        stream: false,
        options: { temperature: 0.3 }
      )

      {
        output: response["response"],
        context: context,
        verified: @verifier.verify_final(JSON.parse(response["response"] || "{}"))
      }
    rescue JSON::ParserError
      {
        output: response["response"],
        context: context,
        verified: { valid: false, errors: ["Could not parse final output as JSON"] }
      }
    end

    private

    def load_agent_components
      return if defined?(@components_loaded)

      require_relative "agent/planner"
      require_relative "agent/executor"
      require_relative "agent/verifier"
      require_relative "agent/loop"
      @components_loaded = true
    end

    def build_default_final_prompt(context)
      <<~PROMPT
        Based on the following execution context, provide a concise summary and final recommendation.

        CONTEXT:
        #{JSON.pretty_generate(context)}

        Provide a clear, actionable summary.
      PROMPT
    end
  end
end
