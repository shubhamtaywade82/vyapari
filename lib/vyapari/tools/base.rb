# frozen_string_literal: true

module Vyapari
  module Tools
    # Base class for all tool implementations
    class Base
      def self.name = raise NotImplementedError
      def self.schema = raise NotImplementedError
      def call(_params) = raise NotImplementedError
    end
  end
end
