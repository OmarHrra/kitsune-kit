# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "spec_helper"
require "kitsune/kit/adapters/transport_factory"

RSpec.describe Kitsune::Kit::Workflows::Doctor do
  let(:root) { Dir.mktmpdir("kitsune-doctor") }
  let(:config) { build_config }
  let(:server) do
    Kitsune::Kit::Adapters::ServerRecord.new(
      id: "server-1", name: config.server.name, status: "active", public_ip: "203.0.113.10",
      region: config.server.region, size: config.server.size, image: config.server.image, tags: config.server.tags
    )
  end
  let(:provider) { Kitsune::Kit::Adapters::FakeProvider.new(servers: [server]) }
  let(:transport) { Kitsune::Kit::Adapters::FakeTransport.new }
  let(:factory) { Kitsune::Kit::Adapters::FakeTransportFactory.new(transport: transport, server: server) }
  let(:store) { Kitsune::Kit::StateStore.new(root: root) }

  before do
    transport.stub("cat", arguments: ["/etc/os-release"], stdout: "ID=ubuntu\nVERSION_ID=\"24.04\"\n")
    transport.stub("sudo", arguments: ["ss", "-lntH"], stdout: "LISTEN 0 128 0.0.0.0:22 0.0.0.0:*\n")
  end

  after { FileUtils.remove_entry(root) }

  it "checks the local runtime and the complete reachable-server toolchain without mutation" do
    result = described_class.new(
      config: config,
      provider: provider,
      state_store: store,
      transport_factory: factory
    ).call

    expect(result).to be_success
    expect(result.value.map(&:name)).to include(
      "Runtime", "Configuration", "SSH key", "Security defaults", "Provider API", "State", "Server",
      "SSH connection", "Remote OS", "Sudo", "Docker", "Docker Compose", "Ports", "Drift"
    )
    expect(provider.calls.map(&:first)).not_to include(:create_server, :delete_server)
    expect(transport.uploads).to be_empty
  end

  it "fails when a private data-service port is publicly listening" do
    private_config = build_config(postgres: { enabled: true })
    transport.stub(
      "sudo",
      arguments: ["ss", "-lntH"],
      stdout: "LISTEN 0 128 0.0.0.0:22 0.0.0.0:*\nLISTEN 0 128 0.0.0.0:5432 0.0.0.0:*\n"
    )

    result = described_class.new(
      config: private_config,
      provider: provider,
      state_store: store,
      transport_factory: factory
    ).call

    expect(result).not_to be_success
    expect(result.value.find { |check| check.name == "Ports" }.message).to include("5432")
  end

  it "reports a missing server as an actionable warning and skips remote commands" do
    result = described_class.new(
      config: config,
      provider: Kitsune::Kit::Adapters::FakeProvider.new,
      state_store: store,
      transport_factory: factory
    ).call

    expect(result).to be_success
    server_check = result.value.find { |check| check.name == "Server" }
    expect(server_check.status).to eq("warn")
    expect(server_check.hint).to include("kit plan")
    expect(transport.calls).to be_empty
  end

  it "reports local key, published-service, provider and state failures without raising" do
    published = build_config(
      key_path: File.join(root, "missing-key"),
      postgres: { enabled: true, publish: true, bind: "0.0.0.0", allowed_cidrs: ["203.0.113.1/32"] }
    )
    failing_provider = Kitsune::Kit::Adapters::FakeProvider.new(
      failures: { validate_credentials: Kitsune::Kit::Errors::AuthenticationError.new("bad token") }
    )
    bad_store = instance_double(Kitsune::Kit::StateStore)
    allow(bad_store).to receive(:read).and_raise(Kitsune::Kit::Errors::ConfigurationError, "bad state")

    result = described_class.new(config: published, provider: failing_provider, state_store: bad_store).call
    checks = result.value.to_h { |check| [check.name, check] }

    expect(result).not_to be_success
    expect(checks.fetch("SSH key").status).to eq("fail")
    expect(checks.fetch("Security defaults").status).to eq("warn")
    expect(checks.fetch("Provider API").status).to eq("fail")
    expect(checks.fetch("State").status).to eq("fail")
  end

  it "distinguishes provider lookup failure, untracked servers, ID mismatch and pending servers" do
    failure = Kitsune::Kit::Errors::ProviderError.new("lookup failed", hint: "retry")
    failed = described_class.new(
      config: config,
      provider: Kitsune::Kit::Adapters::FakeProvider.new(failures: { find_server: failure }),
      state_store: store
    ).call
    expect(failed.value.find { |check| check.name == "Server" }.status).to eq("fail")

    untracked = described_class.new(config: config, provider: provider, state_store: store).call
    expect(untracked.value.find { |check| check.name == "Server" }.message).to include("not tracked")

    store.update("test") { |state| state.tap { |value| value["resources"]["server"] = { "id" => "wrong" } } }
    mismatched = described_class.new(config: config, provider: provider, state_store: store).call
    expect(mismatched.value.find { |check| check.name == "Server" }.status).to eq("fail")

    pending_server = server.with(status: "new")
    pending_provider = Kitsune::Kit::Adapters::FakeProvider.new(servers: [pending_server])
    store.update("test") do |state|
      state["resources"]["server"] = { "id" => pending_server.id }
      state
    end
    pending = described_class.new(config: config, provider: pending_provider, state_store: store).call
    expect(pending.value.find { |check| check.name == "Server" }.status).to eq("warn")
  end

  it "reports unavailable SSH adapters and connection failures" do
    store.update("test") { |state| state.tap { |value| value["resources"]["server"] = { "id" => server.id } } }
    unavailable = described_class.new(config: config, provider: provider, state_store: store).call
    expect(unavailable.value.find { |check| check.name == "SSH connection" }.status).to eq("warn")

    failing_factory = instance_double(Kitsune::Kit::Adapters::TransportFactory)
    allow(failing_factory).to receive(:bootstrap).and_raise(
      Kitsune::Kit::Errors::ConnectionError.new("SSH failed", hint: "check access")
    )
    failed = described_class.new(
      config: config, provider: provider, state_store: store, transport_factory: failing_factory
    ).call
    expect(failed.value.find { |check| check.name == "SSH connection" }.status).to eq("fail")
  end

  it "reports unsupported OS, failed tools and unsafe listening-port state" do
    store.update("test") { |state| state.tap { |value| value["resources"]["server"] = { "id" => server.id } } }
    transport.stub("cat", arguments: ["/etc/os-release"], stdout: "ID=debian\nVERSION_ID=12\n")
    transport.stub("sudo", arguments: ["-n", "true"], exit_status: 1)
    transport.stub("docker", arguments: ["version", "--format", "{{.Server.Version}}"], exit_status: 1)
    transport.stub("docker", arguments: ["compose", "version", "--short"], exit_status: 1)
    transport.stub("sudo", arguments: ["ss", "-lntH"], stdout: "LISTEN 0 128 127.0.0.1:8080 0.0.0.0:*\n")

    result = described_class.new(
      config: config, provider: provider, state_store: store, transport_factory: factory
    ).call
    checks = result.value.to_h { |check| [check.name, check] }
    expect(checks.fetch("Remote OS").status).to eq("fail")
    expect(checks.fetch("Sudo").status).to eq("fail")
    expect(checks.fetch("Docker").status).to eq("warn")
    expect(checks.fetch("Docker Compose").status).to eq("warn")
    expect(checks.fetch("Ports").message).to include("not listening")
  end

  it "reports an inability to inspect ports and managed/orphaned drift" do
    store.update("test") do |state|
      state["resources"]["server"] = { "id" => server.id }
      state["resources"]["orphan"] = { "managed" => true }
      state
    end
    transport.stub("sudo", arguments: ["ss", "-lntH"], exit_status: 1)
    drift = Struct.new(:resource) do
      def plan
        Kitsune::Kit::Change.new(resource: resource, action: "update", summary: "drift")
      end
    end.new("server")

    result = described_class.new(
      config: config, provider: provider, state_store: store, transport_factory: factory, operations: [drift]
    ).call
    checks = result.value.to_h { |check| [check.name, check] }
    expect(checks.fetch("Ports").message).to include("Unable to inspect")
    expect(checks.fetch("Drift").status).to eq("warn")
    expect(checks.fetch("Drift").message).to include("server", "orphan")
  end

  it "uses the server operation state key without reporting false drift" do
    store.update("test") do |state|
      state["resources"]["server"] = server.to_h.transform_keys(&:to_s)
      state
    end
    operation = Kitsune::Kit::Operations::EnsureServer.new(
      config: config, provider: provider, state_store: store
    )

    result = described_class.new(
      config: config, provider: provider, state_store: store, transport_factory: factory, operations: [operation]
    ).call

    expect(result.value.find { |check| check.name == "Drift" }.status).to eq("pass")
  end
end
