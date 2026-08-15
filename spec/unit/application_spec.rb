# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "spec_helper"
require "kitsune/kit/adapters/transport_factory"

RSpec.describe Kitsune::Kit::Application do
  let(:root) { Dir.mktmpdir("kitsune-app") }
  let(:config) { build_config }
  let(:provider) { Kitsune::Kit::Adapters::FakeProvider.new }
  let(:transport) { Kitsune::Kit::Adapters::FakeTransport.new }
  let(:secret_store) { Kitsune::Kit::Adapters::FakeSecretStore.new("POSTGRES_PASSWORD" => "test-secret") }
  let(:factory) { Kitsune::Kit::Adapters::FakeTransportFactory.new(transport: transport) }
  subject(:application) do
    described_class.new(
      config: config,
      provider: provider,
      state_store: Kitsune::Kit::StateStore.new(root: root),
      transport_factory: factory
    )
  end

  it "injects the configured secret-store port into service operations" do
    service_config = build_config(postgres: { enabled: true })
    server = Kitsune::Kit::Adapters::ServerRecord.new(
      id: "server", name: service_config.server.name, status: "active", public_ip: "203.0.113.10",
      region: service_config.server.region, size: service_config.server.size, image: service_config.server.image,
      tags: service_config.server.tags
    )
    service_factory = Kitsune::Kit::Adapters::FakeTransportFactory.new(transport: transport, server: server)
    app = described_class.new(
      config: service_config, provider: provider, state_store: Kitsune::Kit::StateStore.new(root: root),
      transport_factory: service_factory, secret_store: secret_store
    )
    operation = app.service_operation("postgres")

    expect(operation.plan.details.fetch(:fingerprint)).to be_a(String)
    expect(secret_store.fetches).to include("POSTGRES_PASSWORD")
  end

  after { FileUtils.remove_entry(root) }

  it "orders the server before every remote dependency" do
    resources = application.operations.map(&:resource)

    expect(resources).to eq(
      ["server.myapp-test", "user.deploy", "ssh.policy", "firewall", "unattended_upgrades", "swap", "docker", "metrics"]
    )
  end

  it "plans remote work as dependent when the server is absent" do
    changes = application.operations.map(&:plan)

    expect(changes.drop(1)).to all(satisfy { |change| change.details[:depends_on] == "server" })
    expect(provider.servers).to be_empty
  end

  it "supports a provider-only core and adds DNS without constructing remote operations" do
    dns_config = config_with(system: { unattended_upgrades: false, metrics: false }, domains: ["app.example.com"])
    app = described_class.new(
      config: dns_config, provider: provider, state_store: Kitsune::Kit::StateStore.new(root: root)
    )

    expect(app.operations.map(&:resource)).to eq(["server.myapp-test", "dns"])
  end

  it "omits disabled system features and includes both enabled services" do
    service_config = config_with(
      system: { unattended_upgrades: false, metrics: false },
      postgres: { enabled: true }, redis: { enabled: true }
    )
    app = described_class.new(
      config: service_config,
      provider: provider,
      state_store: Kitsune::Kit::StateStore.new(root: root),
      transport_factory: factory
    )

    resources = app.operations.map(&:resource)
    expect(resources).to include("service.postgres", "service.redis")
    expect(resources).not_to include("unattended_upgrades", "metrics")
  end

  it "represents external services without adding local Docker operations" do
    external = config_with(
      system: { unattended_upgrades: false, metrics: false },
      postgres: { enabled: true, mode: "external", host: "db.internal.example" }
    )
    app = described_class.new(
      config: external, provider: provider, state_store: Kitsune::Kit::StateStore.new(root: root),
      transport_factory: factory, secret_store: secret_store
    )

    expect(app.operations.map(&:resource)).not_to include("service.postgres")
  end

  it "plans enabled services before server creation without opening SSH" do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("POSTGRES_PASSWORD", "").and_return("test-secret")
    service_config = config_with(
      system: { unattended_upgrades: false, metrics: false }, postgres: { enabled: true }
    )
    real_factory = Kitsune::Kit::Adapters::TransportFactory.new(
      config: service_config, provider: provider, root: root
    )
    app = described_class.new(
      config: service_config,
      provider: provider,
      state_store: Kitsune::Kit::StateStore.new(root: root),
      transport_factory: real_factory
    )

    service_change = app.operations.map(&:plan).find { |change| change.resource == "service.postgres" }
    expect(service_change.details.fetch(:depends_on)).to eq("docker")
  end

  it "refuses SSH hardening when the independent deploy connection fails" do
    unreachable = Kitsune::Kit::Adapters::FakeTransport.new(reachable: false)
    failing_factory = Kitsune::Kit::Adapters::FakeTransportFactory.new(transport: unreachable)
    app = described_class.new(
      config: config,
      provider: provider,
      state_store: Kitsune::Kit::StateStore.new(root: root),
      transport_factory: failing_factory
    )

    expect { app.send(:verify_deploy_connection) }
      .to raise_error(Kitsune::Kit::Errors::VerificationError, /second SSH connection/)
  end

  it "wires two-phase SSH and firewall policies around fresh deploy-login checks" do
    server = Kitsune::Kit::Adapters::ServerRecord.new(
      id: "server", name: config.server.name, status: "active", public_ip: "203.0.113.10",
      region: config.server.region, size: config.server.size, image: config.server.image, tags: config.server.tags
    )
    live_factory = Kitsune::Kit::Adapters::FakeTransportFactory.new(transport: transport, server: server)
    app = described_class.new(
      config: config,
      provider: provider,
      state_store: Kitsune::Kit::StateStore.new(root: root),
      transport_factory: live_factory
    )

    %w[ssh.policy firewall].each do |resource|
      operation = app.operations.find { |candidate| candidate.resource == resource }
      operation.apply(operation.plan)
    end
    actions = transport.calls.filter_map do |name, data|
      next unless name == :execute && data[:command] == "sudo" && data[:arguments].first == "bash"

      data[:arguments][2]
    end
    expect(actions.each_slice(4).to_a).to eq([%w[apply verify finalize verify_final]] * 2)
    expect(transport.calls.count { |name, _data| name == :reachable }).to eq(4)
  end

  private

  def config_with(system:, domains: [], postgres: {}, redis: {})
    base = build_config(postgres: postgres, redis: redis)
    Kitsune::Kit::Configuration::Config.new(
      version: base.version, environment: base.environment, provider: base.provider, server: base.server,
      ssh: base.ssh, services: base.services,
      system: Kitsune::Kit::Configuration::System.new(
        swap_size_gb: 2, swap_swappiness: 10,
        unattended_upgrades: system.fetch(:unattended_upgrades), metrics: system.fetch(:metrics)
      ),
      dns: Kitsune::Kit::Configuration::Dns.new(domains: domains, ttl: 3600)
    )
  end
end
