# frozen_string_literal: true

require_relative "../errors"
require_relative "../result"
require_relative "../run_journal"
require_relative "base"

module Kitsune
  module Kit
    module Workflows
      class ApplyPlan < Base
        def initialize(config:, operations:, state_store: nil, cancellation: Cancellation.new,
                       event_bus: Events::NullBus.new, clock: Clock.new)
          super(config: config, event_bus: event_bus, clock: clock)
          @operations = operations
          @cancellation = cancellation
          @state_store = state_store
          @journal = RunJournal.new(
            state_store: state_store,
            environment: config.environment,
            run_id: run_id,
            clock: -> { clock.now }
          )
        end

        def call(plan: nil, resume_from: nil)
          return call_unlocked(plan: plan, resume_from: resume_from) unless @state_store

          @state_store.with_execution_lock(config.environment) do
            call_unlocked(plan: plan, resume_from: resume_from)
          end
        end

        private

        def call_unlocked(plan:, resume_from:)
          started_at = monotonic_time
          journal_started = false
          execution = build_execution(plan, resume_from)
          emit("run_started", command: "apply", environment: config.environment, resumed_from: execution[:source_id])
          @journal.start(changes: execution[:changes].map(&:to_h), resumed_from: execution[:source_id])
          journal_started = true
          @last_confirmed = nil
          results = execute(execution)
          finish("success", started_at)
          Result.success(results, metadata: { run_id: run_id, resumed_from: execution[:source_id] })
        rescue StandardError => e
          if journal_started
            emit_recovery_guidance
            finish(failure_status(e), started_at, error: error_code(e))
          end
          raise
        end

        def build_execution(plan, resume_from)
          return fresh_execution(plan) unless resume_from

          source_id, source = @journal.resumable(resume_from == true ? nil : resume_from)
          changes = Plan.from_h(environment: config.environment, changes: source["changes"]).changes
          validate_operation_set!(changes)
          completed = source["steps"].filter_map { |resource, step| resource if step["status"] == "success" }
          { source_id: source_id, changes: changes, completed: completed }
        end

        def fresh_execution(plan)
          changes = plan ? plan.changes : @operations.map(&:plan)
          validate_operation_set!(changes)
          { source_id: nil, changes: changes, completed: [] }
        end

        def validate_operation_set!(changes)
          operation_resources = @operations.map(&:resource)
          change_resources = changes.map(&:resource)
          return if operation_resources == change_resources

          raise Errors::ConfigurationError.new(
            "the saved plan does not match the configured operations",
            hint: "Review the configuration and start a new `kit plan` and `kit apply`."
          )
        end

        def execute(execution)
          execution[:changes].each_with_index.map do |change, index|
            if execution[:completed].include?(change.resource)
              emit("operation_skipped", resource: change.resource, summary: change.summary,
                                        reason: "already_completed")
              next
            end

            execute_change(operation_for(change), change, index: index + 1, total: execution[:changes].length)
          end
        end

        def execute_change(operation, change, index:, total:)
          @cancellation.check!
          started_at = monotonic_time
          @journal.record_step(change.resource, "running")
          emit("operation_started", resource: change.resource, summary: change.summary, action: change.action,
                                    index: index, total: total)
          emit("operation_progressed", resource: change.resource, summary: change.summary, action: change.action,
                                       percent: 0)
          operation.apply(change).tap do
            @journal.record_step(change.resource, "success")
            @last_confirmed = change.resource
            emit("operation_progressed", resource: change.resource, summary: change.summary, action: change.action,
                                         percent: 100)
            emit_success(change, started_at)
          end
        rescue StandardError => e
          @journal.record_step(change.resource, "failure", error: error_code(e))
          emit_failure(change, e)
          raise
        end

        def operation_for(change) = @operations.find { |operation| operation.resource == change.resource }

        def emit_success(change, started_at)
          emit("operation_succeeded", resource: change.resource, summary: change.summary, action: change.action,
                                      duration_ms: elapsed_ms(started_at))
        end

        def emit_failure(change, error)
          emit("operation_failed", resource: change.resource, summary: change.summary,
                                   message: error.message, code: error_code(error))
        end

        def finish(status, started_at, error: nil)
          @journal.finish(status, error: error)
          emit("run_finished", status: status, duration_ms: elapsed_ms(started_at))
        end

        def error_code(error) = error.respond_to?(:code) ? error.code : "unexpected_error"
        def failure_status(error) = error.is_a?(Cancellation::Cancelled) ? "cancelled" : "failure"

        def emit_recovery_guidance
          confirmed = @last_confirmed ? " Last confirmed step: #{@last_confirmed}." : " No step was confirmed."
          emit(
            "warning_emitted",
            message: "Run #{run_id} is incomplete.#{confirmed} Correct the cause, then run `kit resume #{run_id}`."
          )
        end
      end
    end
  end
end
