# frozen_string_literal: true

require "ollama"

# Client for interacting with the Ollama API
# Wraps Ollama::Client for backward compatibility
class Vyapari::Client
  def initialize(base_url: ENV.fetch("OLLAMA_URL", "http://localhost:11434"))
    @ollama_client = Ollama::Client.new(host: base_url)
    @model = ENV.fetch("OLLAMA_MODEL", "llama3.2:3b")
  end

  # Chat interface - maintains backward compatibility
  # Note: Ollama doesn't natively support tools parameter, so we inject tool descriptions into system message
  def chat(messages:, tools: nil)
    # If tools are provided, inject them into the system message
    messages = inject_tools_into_messages(messages, tools) if tools && !tools.empty?

    @ollama_client.chat(
      model: @model,
      messages: messages,
      stream: false
    )
  end

  private

  def inject_tools_into_messages(messages, tools)
    messages = messages.dup
    tool_descriptions = format_tools_for_prompt(tools)

    # Find or create system message
    system_idx = messages.index { |m| m["role"] == "system" || m[:role] == "system" }

    tool_prompt = <<~TOOLS
      Available tools:
      #{tool_descriptions}

      You can call these tools by responding with tool calls in your messages.
    TOOLS

    if system_idx
      # Append to existing system message
      existing_content = messages[system_idx]["content"] || messages[system_idx][:content] || ""
      messages[system_idx] = {
        role: "system",
        content: "#{existing_content}\n\n#{tool_prompt}"
      }
    else
      # Add new system message at the beginning
      messages.unshift({ role: "system", content: tool_prompt })
    end

    messages
  end

  def format_tools_for_prompt(tools)
    return "" unless tools.is_a?(Array)

    tools.map do |tool|
      name = tool["function"]&.dig("name") || tool[:function]&.dig(:name) || tool["name"] || tool[:name]
      desc = tool["function"]&.dig("description") || tool[:function]&.dig(:description) || tool["description"] || tool[:description] || ""
      params = tool["function"]&.dig("parameters") || tool[:function]&.dig(:parameters) || tool["parameters"] || tool[:parameters] || {}

      param_desc = format_parameters(params)
      "- #{name}: #{desc}#{param_desc}"
    end.join("\n")
  end

  def format_parameters(params)
    return "" unless params.is_a?(Hash)

    props = params["properties"] || params[:properties] || {}
    return "" if props.empty?

    param_list = props.map do |name, schema|
      type = schema["type"] || schema[:type] || "string"
      "#{name} (#{type})"
    end.join(", ")

    " Parameters: #{param_list}"
  end
end
