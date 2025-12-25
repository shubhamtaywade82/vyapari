require "net/http"
require "json"

# Client for interacting with the Ollama API
class Vyapari::Client
  def initialize(base_url: ENV.fetch("OLLAMA_URL", "http://localhost:11434"))
    @uri = URI("#{base_url}/api/chat")
  end

  def chat(messages:, tools:)
    req = Net::HTTP::Post.new(@uri, "Content-Type" => "application/json")
    req.body = {
      model: ENV.fetch("OLLAMA_MODEL", "llama3.2:3b"),
      messages: messages,
      tools: tools,
      stream: false
    }.to_json

    res = Net::HTTP.start(@uri.hostname, @uri.port) { |h| h.request(req) }

    raise "Ollama error: #{res.body}" unless res.is_a?(Net::HTTPSuccess)

    JSON.parse(res.body)
  end
end
