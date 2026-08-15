# frozen_string_literal: true

require_relative "../plan"
require_relative "../result"
require_relative "base"

module Kitsune
  module Kit
    module Workflows
      class BuildPlan < Base
        def initialize(config:, operations:, event_bus: Events::NullBus.new, clock: Clock.new)
          super(config: config, event_bus: event_bus, clock: clock)
          @operations = operations
        end

        def call
          started_at = monotonic_time
          emit("run_started", command: "plan", environment: config.environment)
          changes = @operations.map(&:plan)
          plan = Plan.new(environment: config.environment, changes: changes)
          emit(
            "plan_built",
            changed_count: plan.changed_count,
            unchanged_count: plan.changes.length - plan.changed_count,
            destructive: plan.destructive?
          )
          emit("run_finished", status: "success", duration_ms: elapsed_ms(started_at))
          Result.success(plan, metadata: { run_id: run_id })
        end
      end
    end
  end
end
