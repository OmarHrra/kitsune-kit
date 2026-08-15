# frozen_string_literal: true

require_relative "../errors"
require_relative "../result"
require_relative "base"

module Kitsune
  module Kit
    module Workflows
      class ImportServer < Base
        def initialize(config:, provider:, state_store:, event_bus: Events::NullBus.new, clock: Clock.new)
          super(config: config, event_bus: event_bus, clock: clock)
          @provider = provider
          @state_store = state_store
        end

        def call(provider_id:, confirmation:)
          validate_inputs!(provider_id, confirmation)
          @state_store.with_execution_lock(config.environment) do
            import_locked(provider_id.to_s)
          end
        end

        private

        def validate_inputs!(provider_id, confirmation)
          unless provider_id.to_s.match?(/\A[0-9]+\z/)
            raise Errors::ConfigurationError.new(
              "a numeric provider ID is required for server import",
              hint: "Pass --provider-id after copying the exact Droplet ID from the DigitalOcean control panel."
            )
          end
          return if confirmation == config.server.name

          raise Errors::UnsafeOperationError.new(
            "server import was not confirmed",
            hint: "Pass --confirm-import #{config.server.name} only after checking the exact provider ID."
          )
        end

        def import_locked(provider_id)
          state = @state_store.read(config.environment)
          existing_id = state.dig("resources", "server", "id")
          return Result.success(existing_id, metadata: { unchanged: true }) if existing_id.to_s == provider_id
          if existing_id
            raise Errors::UnsafeOperationError.new(
              "state already tracks a different server",
              hint: "Restore/reconcile the existing state instead of replacing its provider ID."
            )
          end

          server = @provider.find_server_by_id(id: provider_id)
          unless server
            raise Errors::ProviderError.new(
              "server does not exist for provider ID #{provider_id}",
              hint: "Copy the exact Droplet ID from DigitalOcean and retry."
            )
          end
          verify_identity!(server)
          record(server)
          Result.success(server, metadata: { imported: true })
        end

        def verify_identity!(server)
          differences = {
            name: [server.name, config.server.name],
            region: [server.region, config.server.region],
            size: [server.size, config.server.size],
            image: [server.image, config.server.image],
            tags: [server.tags, config.server.tags],
            status: [server.status, "active"]
          }
          differences.delete_if do |field, (actual, desired)|
            field == :tags ? (desired - Array(actual)).empty? : actual == desired
          end
          return if differences.empty? && server.public_ip

          differences[:public_ip] = [server.public_ip, "required"] unless server.public_ip
          raise Errors::UnsafeOperationError.new(
            "provider server does not match the configured environment",
            hint: "Do not import it. Correct configuration or recover the original state backup.",
            context: { provider_id: server.id, differences: differences }
          )
        end

        def record(server)
          @state_store.update(config.environment) do |state|
            state["resources"]["server"] = server.to_h.transform_keys(&:to_s).merge(
              "provider" => config.provider.name
            )
            state["operations"] << {
              "resource" => "server.#{config.server.name}", "action" => "import", "status" => "applied"
            }
            state
          end
        end
      end
    end
  end
end
