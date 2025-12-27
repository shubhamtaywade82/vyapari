# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Ollama
  # Core HTTP client for Ollama API
  # Handles all communication with local Ollama server
  class Client
    DEFAULT_HOST = "http://localhost:11434"
    DEFAULT_TIMEOUT = 60

    def initialize(host: DEFAULT_HOST, timeout: DEFAULT_TIMEOUT)
      @host = host
      @timeout = timeout
    end

    # ---------- PUBLIC API ----------

    # Stateless text generation - use for agents, planners, JSON output
    # @param model [String] Model name (e.g., "mistral", "llama3.2")
    # @param prompt [String] Input prompt
    # @param format [Hash, String, nil] JSON schema for structured output, or "json" for JSON mode
    # @param stream [Boolean] Enable streaming responses
    # @param options [Hash] Model options (temperature, top_p, num_ctx, stop, etc.)
    # @param keep_alive [String, nil] Keep model loaded (e.g., "10m", "5m")
    # @return [Hash] Response with "response", "done", token counts, timings
    def generate(model:, prompt:, format: nil, stream: false, options: {}, keep_alive: nil)
      payload = {
        model: model,
        prompt: prompt,
        stream: stream,
        options: options
      }
      payload[:format] = format if format
      payload[:keep_alive] = keep_alive if keep_alive

      if stream
        stream_generate(payload)
      else
        post("/api/generate", payload)
      end
    end

    # Multi-turn conversation - use for chat UIs, human interaction
    # @param model [String] Model name
    # @param messages [Array<Hash>] Message history with role/content
    # @param stream [Boolean] Enable streaming
    # @param options [Hash] Model options
    # @param keep_alive [String, nil] Keep model loaded
    # @return [Hash] Response with "message" containing role/content
    def chat(model:, messages:, stream: false, options: {}, keep_alive: nil)
      payload = {
        model: model,
        messages: messages,
        stream: stream,
        options: options
      }
      payload[:keep_alive] = keep_alive if keep_alive

      if stream
        stream_chat(payload)
      else
        post("/api/chat", payload)
      end
    end

    # Generate embeddings for RAG / vector search
    # @param model [String] Embedding model (e.g., "mxbai-embed-large")
    # @param input [String, Array<String>] Text(s) to embed
    # @return [Hash] Response with "embedding" array
    def embed(model:, input:)
      post("/api/embed", { model: model, input: input })
    end

    # Stream handler for generate endpoint
    # Yields JSON chunks as they arrive
    # @yield [Hash] Streaming response chunks
    def stream(model:, prompt:, format: nil, options: {}, keep_alive: nil, &block)
      payload = {
        model: model,
        prompt: prompt,
        stream: true,
        options: options
      }
      payload[:format] = format if format
      payload[:keep_alive] = keep_alive if keep_alive

      stream_generate(payload, &block)
    end

    # Health check - get Ollama version
    # @return [Hash] Version info
    def version
      get("/api/version")
    end

    # List installed models
    # @return [Hash] Models list with tags
    def tags
      get("/api/tags")
    end

    # Health check - combines version and tags
    # @return [Hash] Health status
    def health
      {
        version: version,
        models: tags
      }
    rescue StandardError => e
      { error: e.message, healthy: false }
    end

    # ---------- INTERNAL ----------

    private

    def post(path, payload)
      uri = URI.join(@host, path)
      http = Net::HTTP.new(uri.host, uri.port)
      http.read_timeout = @timeout

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = JSON.dump(payload)

      response = http.request(request)

      raise Error, "Ollama API error: #{response.code} - #{response.body}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end

    def get(path)
      uri = URI.join(@host, path)
      response = Net::HTTP.get_response(uri)

      raise Error, "Ollama API error: #{response.code} - #{response.body}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end

    def stream_generate(payload, &_block)
      uri = URI.join(@host, "/api/generate")
      http = Net::HTTP.new(uri.host, uri.port)
      http.read_timeout = @timeout

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = JSON.dump(payload)

      buffer = +""
      final_response = nil

      http.request(request) do |response|
        raise Error, "Ollama API error: #{response.code} - #{response.body}" unless response.is_a?(Net::HTTPSuccess)

        response.read_body do |chunk|
          buffer << chunk
          while (line = buffer.slice!(/.+\n/))
            parsed = JSON.parse(line)
            yield parsed if block_given?
            final_response = parsed if parsed["done"]
          end
        end
      end

      final_response || {}
    end

    def stream_chat(payload, &_block)
      uri = URI.join(@host, "/api/chat")
      http = Net::HTTP.new(uri.host, uri.port)
      http.read_timeout = @timeout

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = JSON.dump(payload)

      buffer = +""
      final_response = nil

      http.request(request) do |response|
        raise Error, "Ollama API error: #{response.code} - #{response.body}" unless response.is_a?(Net::HTTPSuccess)

        response.read_body do |chunk|
          buffer << chunk
          while (line = buffer.slice!(/.+\n/))
            parsed = JSON.parse(line)
            yield parsed if block_given?
            final_response = parsed if parsed["done"]
          end
        end
      end

      final_response || {}
    end
  end

  # Custom error class for Ollama API errors
  class Error < StandardError; end
end
