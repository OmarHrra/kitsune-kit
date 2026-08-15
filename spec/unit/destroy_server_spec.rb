# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "spec_helper"

RSpec.describe Kitsune::Kit::Workflows::DestroyServer do
  let(:root) { Dir.mktmpdir("kitsune-destroy") }
  let(:config) { build_config }
  let(:server) do
    Kitsune::Kit::Adapters::ServerRecord.new(
      id: "managed-id", name: config.server.name, status: "active", public_ip: "203.0.113.10",
      region: config.server.region, size: config.server.size, image: config.server.image, tags: config.server.tags
    )
  end
  let(:provider) { Kitsune::Kit::Adapters::FakeProvider.new(servers: [server]) }
  let(:store) { Kitsune::Kit::StateStore.new(root: root) }
  subject(:workflow) { described_class.new(config: config, provider: provider, state_store: store) }

  before do
    store.update("test") do |state|
      state["resources"]["server"] = server.to_h.transform_keys(&:to_s)
      state
    end
  end

  after { FileUtils.remove_entry(root) }

  it "deletes only the exact provider ID after exact-name confirmation" do
    expect(workflow.call(confirmation: config.server.name)).to be_success
    expect(provider.servers).to be_empty
    expect(store.read("test")["resources"]).to be_empty
  end

  it "refuses an ID that now points to a different server" do
    provider.servers[0] = server.with(name: "unrelated")

    expect { workflow.call(confirmation: config.server.name) }
      .to raise_error(Kitsune::Kit::Errors::UnsafeOperationError, /unexpected server/)
    expect(provider.servers).not_to be_empty
  end

  it "clears stale state safely when the exact server is already absent" do
    provider.servers.clear

    expect(workflow.call(confirmation: config.server.name)).to be_success
    expect(provider.calls.map(&:first)).not_to include(:delete_server)
    expect(store.read("test")["resources"]).to be_empty
  end

  it "describes the exact target in a failed confirmation without deleting it" do
    expect { workflow.call(confirmation: "wrong") }
      .to raise_error(Kitsune::Kit::Errors::UnsafeOperationError) do |error|
        expect(error.context).to include(
          provider: "digitalocean", environment: "test", server: config.server.name,
          provider_id: "managed-id", recoverable: false
        )
      end
    expect(provider.servers).to contain_exactly(server)
  end

  it "does not alter DNS when provider deletion fails" do
    dns = instance_double(Kitsune::Kit::Operations::EnsureDnsRecords, rollback: true)
    failure = Kitsune::Kit::Errors::ProviderError.new("delete failed", retryable: true)
    failing_provider = Kitsune::Kit::Adapters::FakeProvider.new(
      servers: [server], failures: { delete_server: failure }
    )
    guarded = described_class.new(
      config: config, provider: failing_provider, state_store: store, dns_operation: dns
    )

    expect { guarded.call(confirmation: config.server.name) }
      .to raise_error(Kitsune::Kit::Errors::ProviderError, /delete failed/)
    expect(dns).not_to have_received(:rollback)
    expect(store.read("test").dig("resources", "server", "id")).to eq("managed-id")
  end

  it "refuses destruction when no exact managed ID is available" do
    store.update("test") do |state|
      state["resources"].delete("server")
      state
    end

    expect { workflow.call(confirmation: config.server.name) }
      .to raise_error(Kitsune::Kit::Errors::UnsafeOperationError, /no managed server ID/)
    expect(provider.servers).to contain_exactly(server)
  end
end
