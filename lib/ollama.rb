# frozen_string_literal: true

# Main Ollama module - provides client and agent interfaces
require_relative "ollama/client"
require_relative "ollama/agent"
require_relative "ollama/chat/session"

# Load agent components explicitly so they're available
require_relative "ollama/agent/tool_descriptor"
require_relative "ollama/agent/tool_registry"
require_relative "ollama/agent/safety_gate"

# Ollama::Agent is the main agent class
# Internal components are in Ollama::Agent namespace
