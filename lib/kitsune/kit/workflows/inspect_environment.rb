# frozen_string_literal: true

require_relative "../result"
require_relative "base"

module Kitsune
  module Kit
    module Workflows
      EnvironmentStatus = Data.define(:environment, :server, :managed_resources, :last_operations) do
        def to_h
          {
            environment: environment,
            server: server&.to_h,
            managed_resources: managed_resources,
            last_operations: last_operations
          }
        end
      end

      class InspectEnvironment < Base
        def initialize(config:, provider:, state_store:, event_bus: Events::NullBus.new, clock: Clock.new)
          super(config: config, event_bus: event_bus, clock: clock)
          @provider = provider
          @state_store = state_store
        end

        def call
          started_at = monotonic_time
          emit("run_started", command: "inspect", environment: config.environment)
          state = @state_store.read(config.environment)
          server = @provider.find_server(name: config.server.name, tags: config.server.tags)
          value = EnvironmentStatus.new(
            environment: config.environment,
            server: server,
            managed_resources: state["resources"],
            last_operations: state["operations"].last(20)
          )
          emit("run_finished", status: "success", duration_ms: elapsed_ms(started_at))
          Result.success(value, metadata: { run_id: run_id })
        end
      end
    end
  end
end
