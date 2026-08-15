# frozen_string_literal: true

module ConfigFactory
  def build_config(environment: "test", key_path: __FILE__, postgres: {}, redis: {})
    Kitsune::Kit::Configuration::Config.new(
      version: 1,
      environment: environment,
      provider: Kitsune::Kit::Configuration::Provider.new,
      server: Kitsune::Kit::Configuration::Server.new(
        name: "myapp-test",
        region: "sfo3",
        size: "s-1vcpu-1gb",
        image: "ubuntu-24-04-x64",
        ssh_key_id: "123",
        tags: ["kitsune-managed"]
      ),
      ssh: Kitsune::Kit::Configuration::Ssh.new(key_path: key_path),
      services: Kitsune::Kit::Configuration::Services.new(
        postgres: build_service(type: :postgres, overrides: postgres),
        redis: build_service(type: :redis, overrides: redis)
      ),
      system: Kitsune::Kit::Configuration::System.new(
        swap_size_gb: 2,
        swap_swappiness: 10,
        unattended_upgrades: true,
        metrics: true,
        metrics_installer_sha256: "a" * 64
      ),
      dns: Kitsune::Kit::Configuration::Dns.new(domains: [], ttl: 3600)
    )
  end

  def build_service(type:, overrides: {})
    overrides = overrides.dup
    compose = overrides.delete(:compose)
    compose = Kitsune::Kit::Configuration::Compose.new(**compose) if compose.is_a?(Hash)
    defaults = if type == :postgres
                 { image: "postgres:17", port: 5432, password_env: "POSTGRES_PASSWORD", mode: "managed", host: nil }
               else
                 { image: "redis:7.2", port: 6379, password_env: "REDIS_PASSWORD", mode: "managed", host: nil }
               end
    Kitsune::Kit::Configuration::Service.new(
      **defaults, enabled: false, publish: false, bind: "127.0.0.1", allowed_cidrs: [],
                  compose: compose || Kitsune::Kit::Configuration::Compose.new, **overrides
    )
  end
end

RSpec.configure do |config|
  config.include ConfigFactory
end
