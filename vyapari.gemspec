# frozen_string_literal: true

require_relative "lib/vyapari/version"

Gem::Specification.new do |spec|
  spec.name = "vyapari"
  spec.version = Vyapari::VERSION
  spec.authors = ["Shubham Taywade"]
  spec.email = ["shubhamtaywade82@gmail.com"]

  spec.summary = "A Ruby gem for merchant and trading operations"
  spec.description = "Vyapari provides functionality for merchant and trading operations in Ruby applications."
  spec.homepage = "https://github.com/shubhamtaywade/vyapari"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  # Uncomment the line below if you want to restrict pushes to a specific server
  # spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/shubhamtaywade/vyapari"
  spec.metadata["changelog_uri"] = "https://github.com/shubhamtaywade/vyapari/blob/master/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/ .rubocop.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Technical analysis libraries for volume-based indicators
  # intrinio/technical-analysis - Comprehensive indicator library
  spec.add_dependency "technical-analysis", "~> 0.1"
  # ruby-technical-analysis - Additional indicators (IMI, Chande Momentum, etc.)
  spec.add_dependency "ruby-technical-analysis", "~> 1.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
