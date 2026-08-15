# frozen_string_literal: true

require "rbconfig"
require_relative "../result"
require_relative "base"

module Kitsune
  module Kit
    module Workflows
      Check = Data.define(:name, :status, :message, :hint) do
        def to_h = { name: name, status: status, message: message, hint: hint }
      end

      class Doctor < Base
        SUPPORTED_UBUNTU = %w[22.04 24.04].freeze

        def initialize(config:, provider:, state_store:, transport_factory: nil, operations: [],
                       event_bus: Events::NullBus.new, clock: Clock.new)
          super(config: config, event_bus: event_bus, clock: clock)
          @provider = provider
          @state_store = state_store
          @transport_factory = transport_factory
          @operations = operations
        end

        def call
          started_at = monotonic_time
          emit("run_started", command: "doctor", environment: config.environment)
          checks = local_checks + infrastructure_checks
          emit_findings(checks)
          status = checks.any? { |check| check.status == "fail" } ? "failure" : "success"
          emit("run_finished", status: status, duration_ms: elapsed_ms(started_at))
          Result.new(status: status.to_sym, value: checks, metadata: { run_id: run_id })
        end

        private

        def local_checks
          [runtime_check, configuration_check, ssh_key_check, security_check, provider_check, state_check]
        end

        def infrastructure_checks
          @server = find_server
          values = [server_check]
          return values unless @server

          values << ssh_connection_check
          return values unless @transport

          values + [ubuntu_check, sudo_check, docker_check, compose_check, ports_check, drift_check]
        end

        def emit_findings(checks)
          checks.reject { |check| check.status == "pass" }.each do |check|
            emit("warning_emitted", message: "#{check.name}: #{check.message}", hint: check.hint,
                                    status: check.status)
          end
        end

        def runtime_check
          supported = Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.2.0")
          check("Runtime", supported ? "pass" : "fail", "Ruby #{RUBY_VERSION} on #{RbConfig::CONFIG['host_os']}",
                supported ? nil : "Install Ruby 3.2 or newer.")
        end

        def configuration_check = check("Configuration", "pass", "Configuration is valid")

        def ssh_key_check
          path = config.ssh.key_path
          unless File.file?(path)
            return check("SSH key", "fail", "Private key does not exist: #{path}",
                         "Set ssh.key_path to an existing private key.")
          end

          mode = File.stat(path).mode & 0o777
          if mode.anybits?(0o077)
            return check("SSH key", "warn", format("Private key mode is %<mode>04o", mode: mode),
                         "Run `chmod 600 #{path}`.")
          end

          check("SSH key", "pass", "Private key permissions are restricted")
        rescue SystemCallError => e
          check("SSH key", "fail", e.message, "Check the configured path and permissions.")
        end

        def security_check
          published = %w[postgres redis].select do |type|
            service = config.services.public_send(type)
            service.enabled && service.mode == "managed" && service.publish
          end
          return check("Security defaults", "pass", "Data services are private") if published.empty?

          check("Security defaults", "warn", "Published services: #{published.join(', ')}",
                "Confirm every allowed CIDR and prefer private Docker networking.")
        end

        def provider_check
          @provider.validate_credentials!
          check("Provider API", "pass", "DigitalOcean credentials and API access are valid")
        rescue Errors::Error => e
          check("Provider API", "fail", e.message, e.hint)
        end

        def state_check
          @state = @state_store.read(config.environment)
          check("State", "pass", "State is readable and schema-compatible")
        rescue Errors::Error => e
          check("State", "fail", e.message, e.hint)
        end

        def find_server
          @provider.find_server(name: config.server.name, tags: config.server.tags)
        rescue Errors::Error => e
          @server_error = e
          nil
        end

        def server_check
          return check("Server", "fail", @server_error.message, @server_error.hint) if @server_error
          return check("Server", "warn", "Server does not exist", "Run `kit plan`, then `kit apply`.") unless @server

          managed_id = @state&.dig("resources", "server", "id")
          unless managed_id
            return check("Server", "warn", "Server exists but is not tracked in local state",
                         "Restore the state backup before changing or destroying this server.")
          end
          if managed_id.to_s != @server.id.to_s
            return check("Server", "fail", "Provider server does not match the managed ID",
                         "Reconcile state without deleting either server by name.")
          end

          status = @server.status == "active" ? "pass" : "warn"
          check("Server", status, "#{@server.name} is #{@server.status}",
                status == "pass" ? nil : "Wait for the server to become active.")
        end

        def ssh_connection_check
          unless @transport_factory
            return check("SSH connection", "warn", "SSH adapter is unavailable", "Run doctor through the CLI.")
          end

          @transport = @transport_factory.bootstrap
          check("SSH connection", "pass", "Host key and public-key login are verified")
        rescue Errors::Error => e
          check("SSH connection", "fail", e.message, e.hint)
        end

        def ubuntu_check
          result = @transport.execute("cat", arguments: ["/etc/os-release"], timeout: 15)
          version = result.stdout[/^VERSION_ID="?([^"\n]+)"?$/, 1]
          ubuntu = result.stdout.match?(/^ID=ubuntu$/)
          supported = result.success? && ubuntu && SUPPORTED_UBUNTU.include?(version)
          check("Remote OS", supported ? "pass" : "fail", "Ubuntu #{version || 'unknown'}",
                supported ? nil : "Use Ubuntu #{SUPPORTED_UBUNTU.join(' or ')} LTS.")
        end

        def sudo_check = command_check("Sudo", "sudo", ["-n", "true"], "Passwordless sudo is available")

        def docker_check
          command_check("Docker", "docker", ["version", "--format", "{{.Server.Version}}"],
                        "Docker Engine is available", status: "warn", hint: "Run `kit docker install`.")
        end

        def compose_check
          command_check("Docker Compose", "docker", ["compose", "version", "--short"],
                        "Docker Compose v2 is available", status: "warn", hint: "Run `kit docker install`.")
        end

        def ports_check
          result = @transport.execute("sudo", arguments: ["ss", "-lntH"], timeout: 15)
          return check("Ports", "fail", "Unable to inspect listening ports") unless result.success?

          ssh_listening = result.stdout.match?(/:#{Regexp.escape(config.ssh.port.to_s)}\s/)
          exposed = private_service_ports.select { |port| result.stdout.match?(/(?:0\.0\.0\.0|\[::\]):#{port}\s/) }
          return check("Ports", "fail", "SSH port #{config.ssh.port} is not listening") unless ssh_listening
          if exposed.any?
            return check("Ports", "fail", "Private data ports are publicly listening: #{exposed.join(', ')}",
                         "Stop the service and inspect its Compose port bindings.")
          end

          check("Ports", "pass", "SSH is listening and private data ports are not public")
        end

        def drift_check
          state = @state || @state_store.read(config.environment)
          planned = @operations.map { |operation| [operation, operation.plan] }
          desired_resources = planned.map { |operation, change| state_key_for(operation, change) }
          drifted = planned.filter_map do |operation, change|
            change.resource if state.dig("resources", state_key_for(operation, change)) && change.changed?
          end
          orphaned = state["resources"].keys - desired_resources
          findings = drifted + orphaned
          return check("Drift", "pass", "Managed resources match the desired configuration") if findings.empty?

          check("Drift", "warn", "Review managed-resource drift: #{findings.uniq.join(', ')}",
                "Run `kit plan`; restore state before adopting or removing existing resources.")
        rescue Errors::Error => e
          check("Drift", "fail", e.message, e.hint)
        end

        def state_key_for(operation, change)
          operation.respond_to?(:state_key) ? operation.state_key : change.resource
        end

        def command_check(name, command, arguments, success_message, status: "fail", hint: nil)
          result = @transport.execute(command, arguments: arguments, timeout: 15)
          return check(name, "pass", success_message) if result.success?

          check(name, status, "Command failed with status #{result.exit_status}", hint)
        end

        def private_service_ports
          %w[postgres redis].filter_map do |type|
            service = config.services.public_send(type)
            service.port if service.enabled && service.mode == "managed" && !service.publish
          end
        end

        def check(name, status, message, hint = nil)
          Check.new(name: name, status: status, message: message, hint: hint)
        end
      end
    end
  end
end
