# frozen_string_literal: true

require "digest"
require_relative "../errors"
require_relative "../plan"
require_relative "../service_compose"
require_relative "service_files"
require_relative "service_firewall"
require_relative "service_backup"
require_relative "service_state"

module Kitsune
  module Kit
    module Operations
      # Service lifecycle coordination intentionally lives together so apply and rollback share one transaction model.
      class EnsureService # rubocop:disable Metrics/ClassLength
        TYPES = %w[postgres redis].freeze
        MARKER_DIRECTORY = "/var/lib/kitsune/state"

        attr_reader :resource

        def initialize(config:, type:, transport_factory:, state_store:, secret_store:, clock: -> { Time.now.utc })
          @config = config
          @type = type.to_s
          raise ArgumentError, "unknown service type: #{@type}" unless TYPES.include?(@type)

          @service = config.services.public_send(@type)
          @transport_factory = transport_factory
          @state_store = state_store
          @secret_store = secret_store
          @resource = "service.#{@type}"
          @managed_state = ServiceState.new(state_store: state_store, environment: config.environment,
                                            resource: resource)
          @compose = ServiceCompose.new(config: config, type: @type, service: @service)
          @clock = clock
        end

        def plan
          return pending_change unless transport_factory.server&.public_ip

          actual = remote_fingerprint
          files.ensure_managed_or_absent!(actual)
          return unchanged_change if actual == fingerprint

          Change.new(
            resource: resource,
            action: actual.empty? ? "create" : "update",
            summary: "#{actual.empty? ? 'Install' : 'Update'} #{@type} service",
            details: safe_details(actual)
          )
        rescue Errors::ConnectionError
          pending_change
        end

        def apply(change)
          return true unless change.changed?

          @firewall_changed = false
          previous_state = managed_state
          password = validated_secret
          files.ensure_managed_or_absent!(remote_fingerprint)
          prepare_backup
          transport.execute("mkdir", arguments: ["-p", service_directory], timeout: 10).then do |result|
            raise_remote!(result, "create service directory")
          end
          @compose.documents.each do |document|
            transport.upload(
              content: document.content, remote_path: files.compose_path(document.filename), mode: "0600"
            )
          end
          transport.upload(content: env_content(password), remote_path: env_path, mode: "0600")
          validate_compose
          start_service
          verify_service
          firewall.reconcile(managed_state)
          @firewall_changed = true
          write_marker
          record_state(change)
          true
        rescue StandardError => e
          recover_failed_apply(previous_state, e)
        end

        def remove
          return false unless managed?

          compose("down", "--remove-orphans", filenames: installed_compose_files)
          firewall.remove
          remove_marker
          @managed_state.record_remove
          true
        end

        def backup
          backup_operation.call(managed_state)
        end

        def rollback
          previous = managed_state
          return false unless previous

          remove
          if files.restore_previous(previous, marker_path: marker_path)
            firewall.restore(previous["previous_state"] || {})
            start_service(filenames: previous.dig("previous_state", "compose_files")) if
              previous.dig("previous_state", "installed") != false
          end
          @managed_state.record_rollback(previous)
          true
        end

        def destroy_data
          previous = managed_state
          return false unless previous

          compose("down", "--volumes", "--remove-orphans", filenames: installed_compose_files)
          files.destroy(previous, marker_path: marker_path)
          @managed_state.delete("destroy_data")
          true
        end

        private

        attr_reader :config, :service, :transport_factory, :state_store, :secret_store

        def transport = @transport ||= transport_factory.deploy
        def project_name = "kitsune-#{config.environment}-#{@type}"
        def service_directory = files.directory
        def env_path = files.env_path
        def marker_path = "#{MARKER_DIRECTORY}/service-#{@type}.sha256"

        def fingerprint
          @fingerprint ||= Digest::SHA256.hexdigest(
            [@compose.fingerprint, service.password_env, secret_digest, service.publish, service.bind,
             *service.allowed_cidrs].join("\0")
          )
        end

        def secret_digest = Digest::SHA256.hexdigest(validated_secret)

        def remote_fingerprint
          result = transport.execute("sudo", arguments: ["cat", marker_path], timeout: 10)
          result.success? ? result.stdout.strip : ""
        end

        def validated_secret
          value = secret_store.fetch(service.password_env)
          if value.match?(/[\n\r\0]/)
            raise Errors::ConfigurationError, "#{service.password_env} contains unsupported control characters"
          end

          value
        end

        def env_content(password) = @compose.env_content(password)

        def validate_compose = compose("config", "--quiet")

        def start_service(filenames: nil)
          compose("up", "--detach", "--wait", "--wait-timeout", "120", filenames: filenames)
        end

        def verify_service
          result = compose("ps", "--status", "running", "--quiet")
          raise Errors::VerificationError, "#{@type} did not reach running state" if result.stdout.strip.empty?
        end

        def compose(*arguments, filenames: nil)
          result = transport.execute(
            "docker",
            arguments: ["compose", "--project-directory", service_directory,
                        *compose_file_arguments(filenames), *arguments],
            timeout: 180
          )
          raise_remote!(result, "docker compose #{arguments.first}")
          result
        end

        def prepare_backup = @backed_up_files = managed? ? files.prepare_backup : []

        def restore_after_failed_apply(previous_state)
          return unless defined?(@backed_up_files)

          firewall.restore_after_failure(previous_state) if @firewall_changed
          safe_compose_down
          files.restore_after_failure(@backed_up_files)
          start_service(filenames: previous_state&.fetch("compose_files", nil)) unless @backed_up_files.empty?
        end

        def recover_failed_apply(previous_state, original_error)
          restore_after_failed_apply(previous_state)
        rescue StandardError => e
          raise Errors::VerificationError.new(
            "#{@type} apply failed and automatic recovery also failed",
            hint: "Stop changes and inspect the service files, container, volume and firewall before retrying.",
            context: { original_error: error_name(original_error), recovery_error: error_name(e) }
          )
        else
          raise original_error
        end

        def safe_compose_down
          transport.execute(
            "docker",
            arguments: ["compose", "--project-directory", service_directory, *compose_file_arguments,
                        "down", "--remove-orphans"],
            timeout: 180
          )
        end

        def write_marker
          transport.execute("sudo", arguments: ["install", "-d", "-m", "0755", MARKER_DIRECTORY], timeout: 10)
          result = transport.execute("sudo", arguments: ["tee", marker_path], stdin: "#{fingerprint}\n", timeout: 10)
          raise_remote!(result, "write service marker")
        end

        def remove_marker
          result = transport.execute("sudo", arguments: ["rm", "-f", marker_path], timeout: 10)
          raise_remote!(result, "remove service marker")
        end

        def record_state(change)
          @managed_state.record_apply(change.action, state_attributes(change))
        end

        def state_attributes(change)
          {
            "managed" => true, "installed" => true, "fingerprint" => fingerprint, "project" => project_name,
            "directory" => service_directory, "published" => service.publish, "port" => service.port,
            "compose_mode" => @compose.mode, "compose_files" => @compose.filenames,
            "compose_fingerprint" => @compose.fingerprint,
            "firewall_rules_added" => firewall.owned_rules, "firewall_drop_added" => firewall.drop_owned,
            "volume" => "#{project_name}_data",
            "previous_fingerprint" => change.details[:actual_fingerprint] || change.details["actual_fingerprint"],
            "backup_directory" => @backed_up_files ? files.backup_directory : nil,
            "backed_up_files" => @backed_up_files || []
          }
        end

        def managed? = @managed_state.managed?
        def managed_state = @managed_state.current
        def installed_compose_files = managed_state&.fetch("compose_files", nil)

        def files
          @files ||= ServiceFiles.new(
            config: config, type: @type, transport: transport, state_store: state_store,
            resource: resource, fingerprint: -> { fingerprint }, compose_filenames: -> { @compose.filenames }
          )
        end

        def firewall
          @firewall ||= ServiceFirewall.new(
            config: config, type: @type, service: @service, transport: transport,
            state_store: state_store, resource: resource
          )
        end

        def backup_operation
          @backup_operation ||= ServiceBackup.new(
            config: config, type: @type, transport: transport,
            compose: ->(*arguments) { compose(*arguments, filenames: installed_compose_files) }, clock: @clock
          )
        end

        def raise_remote!(result, action)
          return if result.success?

          raise Errors::RemoteCommandError.new(
            "unable to #{action} for #{@type}",
            context: { stderr: result.stderr, exit_status: result.exit_status }
          )
        end

        def pending_change
          Change.new(resource: resource, action: "create", summary: "Install #{@type} after Docker is ready",
                     details: safe_details("").merge(depends_on: "docker"))
        end

        def unchanged_change
          Change.new(resource: resource, action: "no_change", summary: "#{@type} is configured",
                     details: safe_details(fingerprint))
        end

        def safe_details(actual)
          {
            image: service.image, published: service.publish,
            bind: service.publish ? service.bind : nil, port: service.publish ? service.port : nil,
            fingerprint: fingerprint,
            actual_fingerprint: actual.empty? ? nil : actual,
            compose: @compose.metadata
          }
        end

        def compose_file_arguments(filenames = nil)
          Array(filenames || @compose.filenames).flat_map { |filename| ["--file", files.compose_path(filename)] }
        end

        def error_name(error) = error.respond_to?(:code) ? error.code : error.class.name
      end
    end
  end
end
