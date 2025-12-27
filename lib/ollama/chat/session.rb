# frozen_string_literal: true

require_relative "../client"

module Ollama
  module Chat
    # Conversational chat session
    # Manages message history and uses /api/chat for multi-turn conversations
    class Session
      def initialize(client: nil, model: "mistral")
        @client = client || Client.new
        @model = model
        @messages = []
      end

      # Set system message
      # @param content [String] System message content
      def system(content)
        @messages << { role: "system", content: content }
        self
      end

      # Send user message and get response
      # @param content [String] User message
      # @param stream [Boolean] Enable streaming
      # @return [String] Assistant response
      def user(content, stream: false)
        @messages << { role: "user", content: content }

        if stream
          stream_response
        else
          response = @client.chat(
            model: @model,
            messages: @messages,
            stream: false
          )

          assistant_message = response["message"]
          @messages << assistant_message
          assistant_message["content"]
        end
      end

      # Get message history
      # @return [Array<Hash>] Message history
      def messages
        @messages.dup
      end

      # Clear message history
      def clear
        @messages = []
        self
      end

      # Stream response (yields chunks)
      # @yield [Hash] Streaming response chunks
      def stream_response(&_block)
        full_response = ""
        @client.chat(
          model: @model,
          messages: @messages,
          stream: true
        ) do |chunk|
          content = chunk.dig("message", "content") || chunk["response"] || ""
          full_response += content
          yield chunk if block_given?
        end

        @messages << { role: "assistant", content: full_response }
        full_response
      end
    end
  end
end
