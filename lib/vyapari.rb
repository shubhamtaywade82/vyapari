# frozen_string_literal: true

require_relative "vyapari/version"
require "dhan_hq"

# Ensure modules exist before loading files
module Vyapari
  module Tools
  end

  module Indicators
  end

  module Trading
  end
end

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
