# frozen_string_literal: true

require_relative "../errors"
require_relative "../result"
require_relative "base"

module Kitsune
  module Kit
    module Workflows
      class DestroyServer < Base
        def initialize(config:, provider:, state_store:, dns_operation: nil, event_bus: Events::NullBus.new,
                       clock: Clock.new)
          super(config: config, event_bus: event_bus, clock: clock)
          @provider = provider
          @state_store = state_store
          @dns_operation = dns_operation
        end

        def call(confirmation:)
          @state_store.with_execution_lock(config.environment) { call_unlocked(confirmation: confirmation) }
        end

        private

        def call_unlocked(confirmation:)
          state = @state_store.read(config.environment)
          managed = state.dig("resources", "server")
          unless managed&.fetch("id", nil)
            raise Errors::UnsafeOperationError.new(
              "no managed server ID exists in state",
              hint: "Import and verify the server before attempting destruction."
            )
          end
          validate_confirmation!(confirmation, managed)
          current = verify_exact_server!(managed)
          started_at = monotonic_time
          emit("run_started", command: "server.destroy", environment: config.environment)
          @provider.delete_server(id: managed.fetch("id")) if current
          @dns_operation&.rollback
          record_destruction(managed.fetch("id"))
          emit("run_finished", status: "success", duration_ms: elapsed_ms(started_at))
          Result.success(managed.fetch("id"), metadata: { run_id: run_id })
        rescue StandardError
          emit("run_finished", status: "failure", duration_ms: 0) if defined?(started_at) && started_at
          raise
        end

        def validate_confirmation!(confirmation, managed)
          return if confirmation == config.server.name

          raise Errors::UnsafeOperationError.new(
            "server destruction was not confirmed",
            hint: "Pass --confirm-destroy #{config.server.name} after reviewing the environment.",
            context: {
              provider: config.provider.name, environment: config.environment,
              server: config.server.name, provider_id: managed["id"], recoverable: false
            }
          )
        end

        def verify_exact_server!(managed)
          current = @provider.find_server_by_id(id: managed.fetch("id"))
          return unless current

          expected_tags = config.server.tags
          return current if current.name == config.server.name && (expected_tags - current.tags).empty?

          raise Errors::UnsafeOperationError.new(
            "managed provider ID points to an unexpected server",
            hint: "Do not delete by name. Reconcile or import state first."
          )
        end

        def record_destruction(id)
          @state_store.update(config.environment) do |state|
            state["resources"].clear
            state["operations"] << { "resource" => "server", "action" => "destroy", "status" => "applied", "id" => id }
            state
          end
        end
      end
    end
  end
end
