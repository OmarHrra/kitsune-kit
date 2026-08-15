# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "spec_helper"

RSpec.describe Kitsune::Kit::Operations::EnsureServer do
  let(:root) { Dir.mktmpdir("kitsune-operation") }
  let(:config) { build_config }
  let(:provider) { Kitsune::Kit::Adapters::FakeProvider.new(servers: servers) }
  let(:store) { Kitsune::Kit::StateStore.new(root: root) }
  let(:servers) { [] }
  subject(:operation) { described_class.new(config: config, provider: provider, state_store: store) }

  after { FileUtils.remove_entry(root) }

  it "plans and creates a missing server, then records its provider ID" do
    change = operation.plan

    expect(change.action).to eq("create")
    server = operation.apply(change)
    expect(server.status).to eq("active")
    expect(store.read("test").dig("resources", "server")).to include(
      "id" => server.id, "provider" => "digitalocean", "region" => "sfo3"
    )
  end

  it "records the provider ID before waiting and resumes without creating a duplicate" do
    timeout = Kitsune::Kit::Errors::TimeoutError.new("not ready")
    failing = Kitsune::Kit::Adapters::FakeProvider.new(failures: { wait_until_ready: timeout })
    failing_operation = described_class.new(config: config, provider: failing, state_store: store)
    change = failing_operation.plan

    expect { failing_operation.apply(change) }.to raise_error(Kitsune::Kit::Errors::TimeoutError)
    expect(store.read("test").dig("resources", "server", "id")).not_to be_nil
    expect(store.read("test")["operations"].last["status"]).to eq("started")

    resumed_provider = Kitsune::Kit::Adapters::FakeProvider.new(servers: failing.servers)
    resumed = described_class.new(config: config, provider: resumed_provider, state_store: store)
    ready = resumed.apply(change)

    expect(ready.status).to eq("active")
    expect(resumed_provider.servers.length).to eq(1)
    expect(resumed_provider.calls.map(&:first)).not_to include(:create_server)
  end

  it "applies the configured maximum timeout to provider readiness" do
    limited = described_class.new(config: config, provider: provider, state_store: store, maximum_timeout: 12.5)

    limited.apply(limited.plan)

    expect(provider.calls).to include([:wait_until_ready, { id: provider.servers.first.id, timeout: 12.5 }])
  end

  it "rejects a non-positive maximum timeout before contacting the provider" do
    expect { described_class.new(config: config, provider: provider, state_store: store, maximum_timeout: 0) }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /greater than zero/)
    expect(provider.calls).to be_empty
  end

  context "when the desired server exists" do
    let(:servers) do
      [Kitsune::Kit::Adapters::ServerRecord.new(
        id: "srv-1",
        name: "myapp-test",
        status: "active",
        public_ip: "203.0.113.1",
        region: "sfo3",
        size: "s-1vcpu-1gb",
        image: "ubuntu-24-04-x64",
        tags: ["kitsune-managed"]
      )]
    end

    it "is idempotent" do
      change = operation.plan

      expect(change.action).to eq("no_change")
      expect(operation.apply(change).id).to eq("srv-1")
      expect(provider.calls.none? { |name, _arguments| name == :create_server }).to be(true)
    end

    it "refuses implicit replacement for immutable drift" do
      servers[0] = servers[0].with(size: "s-2vcpu-2gb")
      change = operation.plan

      expect(change).to be_destructive
      expect { operation.apply(change) }
        .to raise_error(Kitsune::Kit::Errors::UnsafeOperationError, /replacement/)
    end
  end
end
