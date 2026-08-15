# frozen_string_literal: true

require "fileutils"
require_relative "../errors"
require_relative "net_ssh_transport"
require_relative "confirming_host_key_verifier"

module Kitsune
  module Kit
    module Adapters
      class TransportFactory
        BOOTSTRAP_TIMEOUT = 120
        BOOTSTRAP_RETRY_INTERVAL = 5

        def initialize(config:, provider:, root: Dir.pwd, host_key_confirmation: nil, maximum_timeout: nil,
                       sleeper: Kernel, monotonic_clock: nil, bootstrap_timeout: BOOTSTRAP_TIMEOUT)
          if maximum_timeout && maximum_timeout <= 0
            raise Errors::ConfigurationError, "timeout must be greater than zero"
          end
          raise Errors::ConfigurationError, "SSH bootstrap timeout must be greater than zero" if bootstrap_timeout <= 0

          @config = config
          @provider = provider
          @known_hosts = File.expand_path(".kitsune/known_hosts", root)
          @host_key_verifier = ConfirmingHostKeyVerifier.new(&host_key_confirmation)
          @maximum_timeout = maximum_timeout
          @bootstrap_timeout = [bootstrap_timeout, maximum_timeout].compact.min
          @sleeper = sleeper
          @monotonic_clock = monotonic_clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
        end

        def server
          @provider.find_server(name: @config.server.name, tags: @config.server.tags)
        end

        def for(user:)
          current = server
          unless current&.public_ip
            raise Errors::ConnectionError.new(
              "server is not ready for SSH",
              hint: "Apply the server operation first, then resume."
            )
          end
          FileUtils.mkdir_p(File.dirname(@known_hosts), mode: 0o700)
          FileUtils.touch(@known_hosts)
          File.chmod(0o600, @known_hosts)
          NetSshTransport.new(
            host: current.public_ip,
            user: user,
            port: @config.ssh.port,
            key_path: @config.ssh.key_path,
            known_hosts: @known_hosts,
            verify_host_key: @host_key_verifier,
            maximum_timeout: @maximum_timeout
          )
        end

        def deploy = self.for(user: @config.ssh.user)
        def root = self.for(user: "root")

        def bootstrap
          candidate = deploy
          return candidate if candidate.reachable?

          candidate = root
          return candidate if candidate.reachable?

          raise Errors::ConnectionError.new(
            "neither #{@config.ssh.user} nor root can access the server",
            hint: "Verify the SSH key and provider console before changing SSH policy."
          )
        end

        def wait_for_bootstrap
          deadline = monotonic_time + @bootstrap_timeout
          loop do
            return bootstrap
          rescue Errors::ConnectionError
            remaining = deadline - monotonic_time
            break if remaining <= 0

            @sleeper.sleep([BOOTSTRAP_RETRY_INTERVAL, remaining].min)
          end

          raise Errors::ConnectionError.new(
            "SSH did not become reachable within #{@bootstrap_timeout} seconds",
            hint: "Wait for Ubuntu to finish booting and verify that the uploaded public key matches ssh.key_path.",
            context: { timeout: @bootstrap_timeout },
            retryable: true
          )
        end

        private

        def monotonic_time = @monotonic_clock.call
      end

      class FakeTransportFactory
        attr_reader :server_record

        def initialize(transport:, server: nil, root_transport: nil, deploy_transport: nil)
          @transport = transport
          @root_transport = root_transport || transport
          @deploy_transport = deploy_transport || transport
          @server_record = server
        end

        def server = @server_record
        def deploy = @deploy_transport
        def root = @root_transport
        def bootstrap = @deploy_transport.reachable? ? @deploy_transport : @root_transport
        def wait_for_bootstrap = bootstrap
      end
    end
  end
end
