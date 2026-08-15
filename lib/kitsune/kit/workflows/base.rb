# frozen_string_literal: true

require "securerandom"
require_relative "../clock"
require_relative "../events"

module Kitsune
  module Kit
    module Workflows
      class Base
        def initialize(config:, event_bus: Events::NullBus.new, clock: Clock.new)
          @config = config
          @event_bus = event_bus
          @clock = clock
          @run_id = SecureRandom.uuid
        end

        private

        attr_reader :config, :event_bus, :run_id, :clock

        def emit(type, **data)
          event_bus.publish(Events::Event.build(type, run_id: run_id, time: clock.now, **data))
        end

        def monotonic_time = clock.monotonic
        def elapsed_ms(started_at) = ((monotonic_time - started_at) * 1000).round
      end
    end
  end
end
