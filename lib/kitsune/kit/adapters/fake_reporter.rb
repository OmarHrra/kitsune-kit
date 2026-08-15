# frozen_string_literal: true

require_relative "../reporters/reporter"

module Kitsune
  module Kit
    module Adapters
      # Deterministic event sink for exercising complete workflows without a terminal.
      class FakeReporter < Reporters::Reporter
        def initialize
          super
          @events = []
          @mutex = Mutex.new
        end

        def handle(event)
          @mutex.synchronize { @events << event }
          event
        end

        def events = @mutex.synchronize { @events.dup }

        def events_of(type)
          @mutex.synchronize { @events.select { |event| event.type == type.to_s } }
        end

        def clear
          @mutex.synchronize { @events.clear }
          self
        end
      end
    end
  end
end
