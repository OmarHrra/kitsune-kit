# frozen_string_literal: true

require_relative "../errors"
require_relative "../plan"

module Kitsune
  module Kit
    module Operations
      class EnsureServer
        attr_reader :config

        def initialize(config:, provider:, state_store:, maximum_timeout: nil)
          if maximum_timeout && maximum_timeout <= 0
            raise Errors::ConfigurationError, "timeout must be greater than zero"
          end

          @config = config
          @provider = provider
          @state_store = state_store
          @ready_timeout = maximum_timeout || 180
        end

        def plan
          @provider.validate_server_spec!(spec: desired_spec)
          existing = @provider.find_server(name: config.server.name, tags: config.server.tags)
          return create_change unless existing

          differences = differences_for(existing)
          return unchanged_change(existing) if differences.empty?

          Change.new(
            resource: "server.#{config.server.name}",
            action: "update",
            summary: "Server exists with immutable configuration differences",
            details: { id: existing.id, differences: differences, replacement_required: true },
            destructive: true
          )
        end

        def apply(change)
          return current_server(change) unless change.changed?
          if change.action == "update"
            raise Errors::UnsafeOperationError.new(
              "server replacement is required for #{config.server.name}",
              hint: "Destroy the managed server explicitly, then run apply again.",
              context: change.details
            )
          end

          created = @provider.find_server(name: config.server.name, tags: config.server.tags) ||
                    @provider.create_server(spec: desired_spec)
          record_created(created)
          ready = @provider.wait_until_ready(id: created.id, timeout: @ready_timeout)
          record_ready(ready)
          ready
        rescue Errors::Error
          raise
        rescue StandardError => e
          raise Errors::ProviderError.new(
            "server operation failed for #{config.server.name}",
            context: { cause: e.class.name },
            retryable: true
          )
        end

        def resource = "server.#{config.server.name}"
        def state_key = "server"

        private

        def desired_spec
          {
            name: config.server.name,
            region: config.server.region,
            size: config.server.size,
            image: config.server.image,
            ssh_key_id: config.server.ssh_key_id,
            tags: config.server.tags
          }
        end

        def create_change
          Change.new(
            resource: resource,
            action: "create",
            summary: "Create server #{config.server.name}",
            details: desired_spec.except(:ssh_key_id)
          )
        end

        def unchanged_change(existing)
          Change.new(
            resource: resource,
            action: "no_change",
            summary: "Server #{config.server.name} is ready",
            details: { id: existing.id, public_ip: existing.public_ip, status: existing.status }
          )
        end

        def differences_for(existing)
          {
            region: [existing.region, config.server.region],
            size: [existing.size, config.server.size],
            image: [existing.image, config.server.image]
          }.reject { |_key, (actual, desired)| actual.nil? || actual == desired }
        end

        def current_server(_change)
          @provider.find_server(name: config.server.name, tags: config.server.tags) ||
            raise(Errors::VerificationError, "server disappeared after planning")
        end

        def record_created(server)
          @state_store.update(config.environment) do |state|
            state["resources"]["server"] = state_record(server)
            state["operations"] << { "resource" => resource, "action" => "create", "status" => "started" }
            state
          end
        end

        def record_ready(server)
          @state_store.update(config.environment) do |state|
            state["resources"]["server"] = state_record(server)
            state["operations"] << { "resource" => resource, "action" => "create", "status" => "applied" }
            state
          end
        end

        def state_record(server)
          server.to_h.transform_keys(&:to_s).merge("provider" => config.provider.name)
        end
      end
    end
  end
end
