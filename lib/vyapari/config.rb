module Vyapari
  class Config
    def self.configure_dhan!
      DhanHQ.configure_with_env
      DhanHQ.logger.level = (ENV["DHAN_LOG_LEVEL"] || "INFO")
                            .upcase
                            .then { |lvl| Logger.const_get(lvl) }
    end
  end
end
