# frozen_string_literal: true

require "json"

module Vyapari
  # Agent class for managing tool interactions with Ollama
  class Agent
    MAX_STEPS = 8

    def initialize(client: Client.new, registry: default_registry, logger: nil)
      @client = client
      @registry = registry
      @messages = []
      @logger = logger || default_logger
      @step = 0
    end

    def run(query)
      @messages << { role: "user", content: query }
      @logger.info "🚀 Starting agent with query: #{query}"

      MAX_STEPS.times do |step_num|
        @step = step_num + 1
        @logger.info "\n📊 Step #{@step}/#{MAX_STEPS}"

        response = @client.chat(
          messages: @messages,
          tools: @registry.tool_schemas
        )

        msg = response.fetch("message")
        @messages << msg

        unless msg["tool_calls"]
          @logger.info "✅ Agent completed. Final response: #{msg["content"]}"
          return msg["content"]
        end

        tool_calls = msg["tool_calls"]
        @logger.info "🔧 LLM selected #{tool_calls.length} tool(s): #{tool_calls.map do |tc|
          tc["function"]["name"]
        end.join(", ")}"

        tool_calls.each_with_index do |call, index|
          tool_name = call["function"]["name"]
          arguments = call["function"]["arguments"]
          parsed_args = arguments.is_a?(String) ? JSON.parse(arguments) : arguments

          @logger.info "\n  🛠️  Tool #{index + 1}/#{tool_calls.length}: #{tool_name}"
          @logger.info "     Parameters: #{parsed_args.inspect}"

          begin
            tool_class = @registry.fetch(tool_name)
            tool = tool_class.new

            result = tool.call(parsed_args)
            result_summary = result.is_a?(Hash) ? result.keys.join(", ") : result.to_s[0..100]
            @logger.info "     ✅ Result: #{result_summary}"

            @messages << {
              role: "tool",
              tool_call_id: call["id"],
              content: result.is_a?(String) ? result : result.to_json
            }
          rescue StandardError => e
            @logger.error "     ❌ Error: #{e.message}"
            raise
          end
        end

        # Log potential next steps
        @logger.info "     🔄 Waiting for LLM to decide next action..."
      end

      raise "Agent did not converge after #{MAX_STEPS} steps"
    end

    private

    def default_registry
      registry = Tools::Registry.new
      registry.register(Tools::RecommendTrade)
      registry.register(Tools::FetchOptionChain)
      registry.register(Tools::AnalyzeTrend)
      registry.register(Tools::FetchIntradayHistory)
      registry.register(Tools::FindInstrument)
      registry
    end

    def default_logger
      require "logger"
      logger = Logger.new($stdout)
      logger.level = ENV["VYAPARI_LOG_LEVEL"] ? Logger.const_get(ENV["VYAPARI_LOG_LEVEL"].upcase) : Logger::INFO
      logger.formatter = proc do |_severity, datetime, _progname, msg|
        "[#{datetime.strftime("%H:%M:%S")}] #{msg}\n"
      end
      logger
    end

    attr_reader :client, :registry, :messages, :logger, :step
  end
end
