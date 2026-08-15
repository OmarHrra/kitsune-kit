# frozen_string_literal: true

require "digest"
require_relative "../errors"
require_relative "../plan"

module Kitsune
  module Kit
    module Operations
      class RemoteScript
        MARKER_DIRECTORY = "/var/lib/kitsune/state"

        attr_reader :resource

        def initialize(config:, transport_factory:, state_store:, resource:, script_path:, arguments: [],
                       transport_roles: { apply: :deploy }, verification: {})
          @config = config
          @transport_factory = transport_factory
          @state_store = state_store
          @resource = resource
          @script_path = script_path
          @arguments = arguments.map(&:to_s).freeze
          @transport_roles = transport_roles
          @post_verify = verification[:callback]
          @finalize_action = verification[:finalize_action]
          @rollback_on_failure = verification.fetch(:rollback_on_failure, false)
        end

        def plan
          return pending_change unless transport_factory.server&.public_ip

          actual = remote_fingerprint
          return unchanged_change if actual == fingerprint

          Change.new(
            resource: resource,
            action: actual.empty? ? "create" : "update",
            summary: actual.empty? ? "Configure #{resource}" : "Update #{resource}",
            details: { fingerprint: fingerprint, actual_fingerprint: actual.empty? ? nil : actual }
          )
        rescue Errors::ConnectionError
          pending_change
        end

        def apply(change)
          return true unless change.changed?

          remote = "/tmp/kitsune-#{safe_resource}-#{fingerprint[0, 12]}.sh"
          applied = false
          current_transport.with_session do
            current_transport.upload(content: script, remote_path: remote, mode: "0700")
            execute_script(remote, "apply")
            applied = true
            execute_script(remote, "verify")
            @post_verify&.call
            finalize(remote)
            write_marker
            record_state(change)
            true
          rescue StandardError => e
            recover_verified_transition(remote, e) if applied && @rollback_on_failure
            raise e
          ensure
            cleanup(remote)
          end
        end

        def rollback
          state = state_store.read(config.environment).dig("resources", resource)
          return false unless state && state["managed"]

          remote = "/tmp/kitsune-#{safe_resource}-rollback.sh"
          rollback_transport.upload(content: script, remote_path: remote, mode: "0700")
          execute_script(remote, "rollback", transport: rollback_transport)
          rollback_transport.execute("sudo", arguments: ["rm", "-f", marker_path], timeout: 10)
          state_store.update(config.environment) do |current|
            current["resources"].delete(resource)
            current["operations"] << { "resource" => resource, "action" => "rollback", "status" => "applied" }
            current
          end
          true
        ensure
          cleanup(remote, transport: rollback_transport) if defined?(remote) && remote
        end

        private

        attr_reader :config, :transport_factory, :state_store

        def script = @script ||= File.read(@script_path)
        def fingerprint = @fingerprint ||= Digest::SHA256.hexdigest([script, *@arguments].join("\0"))
        def safe_resource = resource.tr(".", "-")
        def marker_path = "#{MARKER_DIRECTORY}/#{safe_resource}.sha256"

        def current_transport
          @current_transport ||= transport_factory.public_send(@transport_roles.fetch(:apply, :deploy))
        end

        def rollback_transport
          role = @transport_roles.fetch(:rollback) { @transport_roles.fetch(:apply, :deploy) }
          @rollback_transport ||= transport_factory.public_send(role)
        end

        def remote_fingerprint
          result = current_transport.execute("sudo", arguments: ["cat", marker_path], timeout: 10)
          result.success? ? result.stdout.strip : ""
        end

        def execute_script(remote, action, transport: current_transport)
          result = transport.execute(
            "sudo",
            arguments: ["bash", remote, action, *@arguments],
            timeout: 300
          )
          return result if result.success?

          raise Errors::RemoteCommandError.new(
            "#{resource} #{action} failed with status #{result.exit_status}",
            hint: "Review the remote command error and resume apply after correcting it.",
            context: { stderr: result.stderr, stdout: result.stdout }
          )
        end

        def finalize(remote)
          return unless @finalize_action

          execute_script(remote, @finalize_action)
          execute_script(remote, "verify_final")
          @post_verify&.call
        end

        def write_marker
          directory = current_transport.execute(
            "sudo", arguments: ["install", "-d", "-m", "0755", MARKER_DIRECTORY], timeout: 10
          )
          raise_remote_result!(directory, "create marker directory")
          marker = current_transport.execute(
            "sudo", arguments: ["tee", marker_path], stdin: "#{fingerprint}\n", timeout: 10
          )
          raise_remote_result!(marker, "write marker")
          mode = current_transport.execute("sudo", arguments: ["chmod", "0644", marker_path], timeout: 10)
          raise_remote_result!(mode, "secure marker")
        end

        def raise_remote_result!(result, action)
          return if result.success?

          raise Errors::RemoteCommandError.new("unable to #{action} for #{resource}",
                                               context: { stderr: result.stderr })
        end

        def record_state(change)
          state_store.update(config.environment) do |state|
            state["resources"][resource] = {
              "managed" => true,
              "fingerprint" => fingerprint,
              "action" => change.action
            }
            state["operations"] << { "resource" => resource, "action" => change.action, "status" => "applied" }
            state
          end
        end

        def pending_change
          Change.new(
            resource: resource,
            action: "create",
            summary: "Configure #{resource} after the server is ready",
            details: { fingerprint: fingerprint, depends_on: "server" }
          )
        end

        def unchanged_change
          Change.new(
            resource: resource,
            action: "no_change",
            summary: "#{resource} is configured",
            details: { fingerprint: fingerprint }
          )
        end

        def cleanup(remote, transport: current_transport)
          transport.execute("rm", arguments: ["-f", remote], timeout: 10)
        rescue StandardError
          nil
        end

        def recover_verified_transition(remote, original_error)
          execute_script(remote, "rollback")
          marker = current_transport.execute("sudo", arguments: ["rm", "-f", marker_path], timeout: 10)
          raise_remote_result!(marker, "remove marker during recovery")
          state_store.update(config.environment) do |state|
            if state["resources"].delete(resource)
              state["operations"] << {
                "resource" => resource, "action" => "recover", "status" => "applied"
              }
            end
            state
          end
        rescue StandardError => e
          raise Errors::VerificationError.new(
            "#{resource} verification failed and the preserved SSH session could not restore it",
            hint: "Keep the current terminal open and use provider-console access before retrying.",
            context: {
              original_error: error_name(original_error), recovery_error: error_name(e)
            }
          )
        end

        def error_name(error) = error.respond_to?(:code) ? error.code : error.class.name
      end
    end
  end
end
