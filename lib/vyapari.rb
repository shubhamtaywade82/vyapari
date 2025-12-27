# frozen_string_literal: true

require_relative "vyapari/version"

# Suppress warnings from DhanHQ gem about optional technical analysis dependencies
original_verbosity = $VERBOSE
$VERBOSE = nil
begin
  require "dhan_hq"
ensure
  $VERBOSE = original_verbosity
end

# Ensure modules exist before loading files
module Vyapari
  module Tools
    module Swing
    end
  end

  module Options
  end

  module Swing
  end

  module Indicators
  end

  module Trading
  end
end

# Load Ollama module
require_relative "ollama"

# Dynamically require all Ruby files in lib/vyapari
vyapari_dir = File.join(__dir__, "vyapari")
files = Dir.glob(File.join(vyapari_dir, "**", "*.rb"))
           .reject { |f| f.end_with?("version.rb") } # Already required above
           .sort_by do |f|
             # Load base.rb and tools/base.rb first, then others
             case f
             when /base\.rb$/
               0
             when %r{tools/}
               1
             else
               2
             end
           end
files.each do |file|
  require_relative file.sub("#{__dir__}/", "").sub(/\.rb$/, "")
end

# Dynamically require all Ruby files in lib/indicators
indicators_dir = File.join(__dir__, "indicators")
Dir.glob(File.join(indicators_dir, "**", "*.rb")).each do |file|
  require_relative file.sub("#{__dir__}/", "").sub(/\.rb$/, "")
end

# Dynamically require all Ruby files in lib/trading
trading_dir = File.join(__dir__, "trading")
Dir.glob(File.join(trading_dir, "**", "*.rb")).each do |file|
  require_relative file.sub("#{__dir__}/", "").sub(/\.rb$/, "")
end

module Vyapari
  class Error < StandardError; end
  # Your code goes here...
end
