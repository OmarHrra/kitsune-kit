# frozen_string_literal: true

module Kitsune
  module Kit
    module Tui
      class Actions
        def initialize(application:, cancellation: Cancellation.new)
          @application = application
          @cancellation = cancellation
          @last_plan = nil
        end

        def status
          Workflows::InspectEnvironment.new(
            config: app.config, provider: app.provider, state_store: app.state_store, event_bus: app.event_bus
          ).call
        end

        def plan
          workflow = Workflows::BuildPlan.new(config: app.config, operations: app.operations,
                                              event_bus: app.event_bus)
          workflow.call.tap do |result|
            @last_plan = result.value
          end
        end

        def doctor
          Workflows::Doctor.new(
            config: app.config,
            provider: app.provider,
            state_store: app.state_store,
            transport_factory: app.transport_factory,
            operations: app.operations,
            event_bus: app.event_bus
          ).call
        end

        def apply
          @last_plan ||= plan.value
          raise Errors::UnsafeOperationError, "the plan contains destructive changes" if @last_plan.destructive?
          return Result.success([], metadata: { unchanged: true }) unless @last_plan.changed?

          Workflows::ApplyPlan.new(
            config: app.config, operations: app.operations, state_store: app.state_store, event_bus: app.event_bus,
            cancellation: @cancellation
          ).call(plan: @last_plan)
        ensure
          @last_plan = nil
          reset_cancellation
        end

        def resume
          Workflows::ApplyPlan.new(
            config: app.config, operations: app.operations, state_store: app.state_store, event_bus: app.event_bus,
            cancellation: @cancellation
          ).call(resume_from: true)
        ensure
          reset_cancellation
        end

        def cancel = @cancellation.cancel!

        private

        attr_reader :application
        alias app application

        def reset_cancellation = @cancellation = Cancellation.new
      end
    end
  end
end
