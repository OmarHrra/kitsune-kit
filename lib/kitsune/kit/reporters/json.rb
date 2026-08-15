# frozen_string_literal: true

require "json"
require_relative "reporter"

module Kitsune
  module Kit
    module Reporters
      class Json < Reporter
        attr_reader :events

        def initialize(output: $stdout, secret_filter: SecretFilter.new)
          super()
          @output = output
          @secret_filter = secret_filter
          @events = []
        end

        def handle(event)
          @events << @secret_filter.filter(event.to_h)
        end

        def flush(result: nil, command: nil, environment: nil)
          started = event("run_started", reverse: true)
          finished = event("run_finished", reverse: true)
          payload = {
            schema_version: 1,
            command: command || started&.dig(:data, :command),
            environment: environment || started&.dig(:data, :environment),
            run_id: started&.dig(:run_id) || result&.metadata&.dig(:run_id),
            status: (result&.status || status_from_events).to_s,
            duration_ms: finished&.dig(:data, :duration_ms),
            result: @secret_filter.filter(serialize(result&.value)),
            warnings: @secret_filter.filter(result&.warnings || []),
            events: @events
          }
          @output.puts(::JSON.generate(payload))
          payload
        end

        private

        def event(type, reverse: false)
          source = reverse ? @events.reverse_each : @events.each
          source.find { |item| item[:type] == type }
        end

        def status_from_events
          @events.reverse_each do |event|
            return event.dig(:data, :status) if event[:type] == "run_finished"
          end
          "unknown"
        end

        def serialize(value)
          return value.map { |item| serialize(item) } if value.is_a?(Array)
          return value.to_h { |key, item| [key, serialize(item)] } if value.is_a?(Hash)
          return serialize(value.to_h) if value.respond_to?(:to_h)

          value
        end
      end
    end
  end
end
