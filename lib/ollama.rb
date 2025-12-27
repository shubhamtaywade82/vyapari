# frozen_string_literal: true

# Main Ollama module - provides client and agent interfaces
require_relative "ollama/client"
require_relative "ollama/agent"
require_relative "ollama/chat/session"

# Ollama::Agent is the main agent class
# Internal components are in Ollama::Agent::Internal namespace
