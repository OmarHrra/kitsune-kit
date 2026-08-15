# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "spec_helper"

RSpec.describe Kitsune::Kit::Workflows::ImportServer do
  let(:root) { Dir.mktmpdir("kitsune-import") }
  let(:config) { build_config }
  let(:server) do
    Kitsune::Kit::Adapters::ServerRecord.new(
      id: "123456", name: config.server.name, status: "active", public_ip: "203.0.113.10",
      region: config.server.region, size: config.server.size, image: config.server.image, tags: config.server.tags
    )
  end
  let(:provider) { Kitsune::Kit::Adapters::FakeProvider.new(servers: [server]) }
  let(:store) { Kitsune::Kit::StateStore.new(root: root) }
  subject(:workflow) { described_class.new(config: config, provider: provider, state_store: store) }

  after { FileUtils.remove_entry(root) }

  it "imports an exact provider ID and is idempotent" do
    result = workflow.call(provider_id: server.id, confirmation: config.server.name)

    expect(result).to be_success
    expect(store.read("test").dig("resources", "server")).to include(
      "id" => server.id, "provider" => "digitalocean", "region" => config.server.region
    )
    expect(workflow.call(provider_id: server.id, confirmation: config.server.name).metadata)
      .to include(unchanged: true)
  end

  it "requires an ID and exact confirmation before reading the provider" do
    expect { workflow.call(provider_id: nil, confirmation: config.server.name) }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /provider ID/)
    expect { workflow.call(provider_id: server.id, confirmation: "wrong") }
      .to raise_error(Kitsune::Kit::Errors::UnsafeOperationError, /not confirmed/)
    expect(provider.calls).to be_empty
  end

  it "rejects missing, mismatched and conflicting server identities" do
    expect { workflow.call(provider_id: "999999", confirmation: config.server.name) }
      .to raise_error(Kitsune::Kit::Errors::ProviderError, /does not exist/)

    provider.servers[0] = server.with(size: "s-2vcpu-2gb")
    expect { workflow.call(provider_id: server.id, confirmation: config.server.name) }
      .to raise_error(Kitsune::Kit::Errors::UnsafeOperationError, /does not match/)

    store.update("test") do |state|
      state["resources"]["server"] = { "id" => "other" }
      state
    end
    expect { workflow.call(provider_id: server.id, confirmation: config.server.name) }
      .to raise_error(Kitsune::Kit::Errors::UnsafeOperationError, /different server/)
  end
end
