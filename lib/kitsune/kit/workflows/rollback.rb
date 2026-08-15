# frozen_string_literal: true

require_relative "../result"
require_relative "base"

module Kitsune
  module Kit
    module Workflows
      class Rollback < Base
        def initialize(config:, operations:, state_store: nil, event_bus: Events::NullBus.new, clock: Clock.new)
          super(config: config, event_bus: event_bus, clock: clock)
          @operations = operations
          @state_store = state_store
        end

        def call
          return call_unlocked unless @state_store

          @state_store.with_execution_lock(config.environment) { call_unlocked }
        end

        private

        def call_unlocked
          started_at = monotonic_time
          emit("run_started", command: "rollback", environment: config.environment)
          rolled_back = @operations.reverse.filter_map { |operation| rollback_operation(operation) }
          emit("run_finished", status: "success", duration_ms: elapsed_ms(started_at))
          Result.success(rolled_back, metadata: { run_id: run_id })
        rescue StandardError
          emit("run_finished", status: "failure", duration_ms: elapsed_ms(started_at))
          raise
        end

        def rollback_operation(operation)
          return unless operation.respond_to?(:rollback)

          started_at = monotonic_time
          emit("operation_started", resource: operation.resource, summary: "Rollback #{operation.resource}",
                                    action: "rollback")
          changed = operation.rollback
          emit(
            "operation_succeeded",
            resource: operation.resource,
            summary: changed ? "Rolled back #{operation.resource}" : "#{operation.resource} was not managed",
            action: "rollback",
            duration_ms: elapsed_ms(started_at)
          )
          operation.resource if changed
        end
      end
    end
  end
end
