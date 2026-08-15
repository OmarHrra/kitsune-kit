# frozen_string_literal: true

require_relative "adapters/digitalocean_provider"
require_relative "adapters/transport_factory"
require_relative "configuration"
require_relative "events"
require_relative "operations/ensure_server"
require_relative "operations/ensure_dns_records"
require_relative "operations/ensure_service"
require_relative "state_store"

module Kitsune
  module Kit
    class Application
      attr_reader :config, :event_bus, :provider, :state_store, :transport_factory, :secret_store

      def self.build(root:, environment:, config_path: nil, overrides: {}, env: ENV, event_bus: Events::Bus.new,
                     host_key_confirmation: nil, maximum_timeout: nil)
        config = Configuration::Loader.new(root: root, env: env, config_path: config_path)
                                      .load(environment: environment, overrides: overrides)
        token = env.fetch(config.provider.token_env, "")
        provider = Adapters::DigitalOceanProvider.new(token: token, maximum_timeout: maximum_timeout)
        state_store = StateStore.new(root: root)
        transport_factory = Adapters::TransportFactory.new(
          config: config,
          provider: provider,
          root: root,
          host_key_confirmation: host_key_confirmation,
          maximum_timeout: maximum_timeout
        )
        new(
          config: config,
          provider: provider,
          state_store: state_store,
          transport_factory: transport_factory,
          secret_store: SecretStores::Environment.new(env: env),
          event_bus: event_bus,
          maximum_timeout: maximum_timeout
        )
      end

      def initialize(config:, provider:, state_store:, transport_factory: nil, event_bus: Events::Bus.new,
                     secret_store: SecretStores::Environment.new, maximum_timeout: nil)
        @config = config
        @provider = provider
        @state_store = state_store
        @transport_factory = transport_factory
        @secret_store = secret_store
        @event_bus = event_bus
        @maximum_timeout = maximum_timeout
      end

      def operations
        values = [Operations::EnsureServer.new(
          config: config, provider: provider, state_store: state_store, maximum_timeout: @maximum_timeout
        )]
        values.concat(remote_operations) if @transport_factory
        values.concat(service_operations) if @transport_factory
        if config.dns.domains.any?
          values << Operations::EnsureDnsRecords.new(config: config, provider: provider, state_store: state_store)
        end
        values
      end

      def service_operation(type)
        Operations::EnsureService.new(
          config: config,
          type: type,
          transport_factory: @transport_factory,
          state_store: state_store,
          secret_store: secret_store
        )
      end

      private

      def remote_operations
        values = [user_operation, ssh_operation, firewall_operation]
        if config.system.unattended_upgrades
          values << remote(resource: "unattended_upgrades",
                           script: script("unattended.sh"))
        end
        values << swap_operation
        values << docker_operation
        if config.system.metrics
          values << remote(resource: "metrics", script: script("metrics.sh"),
                           arguments: [config.system.metrics_installer_sha256])
        end
        values
      end

      def user_operation
        remote(
          resource: "user.#{config.ssh.user}",
          script: script("user.sh"),
          arguments: [config.ssh.user],
          role: :wait_for_bootstrap,
          rollback_role: :root,
          post_verify: method(:verify_deploy_connection)
        )
      end

      def ssh_operation
        remote(
          resource: "ssh.policy", script: script("ssh.sh"), arguments: [config.ssh.user],
          post_verify: method(:verify_deploy_connection), finalize_action: "finalize", rollback_on_failure: true
        )
      end

      def firewall_operation
        remote(
          resource: "firewall",
          script: script("firewall.sh"),
          arguments: [config.ssh.port, *config.ssh.allowed_cidrs],
          post_verify: method(:verify_deploy_connection),
          finalize_action: "finalize",
          rollback_on_failure: true
        )
      end

      def swap_operation
        remote(
          resource: "swap",
          script: script("swap.sh"),
          arguments: [config.system.swap_size_gb, config.system.swap_swappiness]
        )
      end

      def docker_operation
        remote(resource: "docker", script: script("docker.sh"), arguments: [config.ssh.user])
      end

      def verify_deploy_connection
        return if @transport_factory.deploy.reachable?

        raise Errors::VerificationError.new(
          "the deploy user cannot open a second SSH connection",
          hint: "Root access remains enabled; inspect authorized_keys and retry."
        )
      end

      def script(name) = File.expand_path("scripts/#{name}", __dir__)

      def remote(resource:, script:, arguments: [], role: :deploy, rollback_role: nil, post_verify: nil,
                 finalize_action: nil, rollback_on_failure: false)
        Operations::RemoteScript.new(
          config: config,
          transport_factory: @transport_factory,
          state_store: state_store,
          resource: resource,
          script_path: script,
          arguments: arguments,
          transport_roles: { apply: role, rollback: rollback_role || role },
          verification: {
            callback: post_verify, finalize_action: finalize_action, rollback_on_failure: rollback_on_failure
          }
        )
      end

      def service_operations
        %w[postgres redis].filter_map do |type|
          service = config.services.public_send(type)
          next unless service.enabled && service.mode == "managed"

          service_operation(type)
        end
      end
    end
  end
end
