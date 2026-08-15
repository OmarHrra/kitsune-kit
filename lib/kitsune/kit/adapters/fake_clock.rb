# frozen_string_literal: true

require_relative "../clock"

module Kitsune
  module Kit
    module Adapters
      class FakeClock < Clock
        attr_reader :now, :monotonic, :sleeps

        def initialize(now: Time.utc(2026, 1, 1), monotonic: 0.0)
          super()
          @now = now.utc
          @monotonic = Float(monotonic)
          @sleeps = []
        end

        def sleep(seconds)
          seconds = Float(seconds)
          @sleeps << seconds
          advance(seconds)
          seconds
        end

        def advance(seconds)
          seconds = Float(seconds)
          @now += seconds
          @monotonic += seconds
          self
        end
      end
    end
  end
end
