module Vyapari
  module DevHelpers
    def nifty
      @nifty ||= DhanHQ::Models::Instrument.find("IDX_I", "NIFTY")
    end

    def banknifty
      @banknifty ||= DhanHQ::Models::Instrument.find("IDX_I", "BANKNIFTY")
    end
  end
end