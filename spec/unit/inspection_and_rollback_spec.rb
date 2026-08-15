# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "spec_helper"

RSpec.describe "inspection and rollback workflows" do
  let(:root) { Dir.mktmpdir("kitsune-inspect") }
  let(:config) { build_config }
  let(:store) { Kitsune::Kit::StateStore.new(root: root) }
  let(:provider) { Kitsune::Kit::Adapters::FakeProvider.new }
  let(:events) { [] }
  let(:bus) { Kitsune::Kit::Events::Bus.new.tap { |value| value.subscribe { |event| events << event } } }

  after { FileUtils.remove_entry(root) }

  it "serializes an environment with and without a server" do
    empty = Kitsune::Kit::Workflows::InspectEnvironment.new(
      config: config, provider: provider, state_store: store, event_bus: bus
    ).call
    expect(empty.value.to_h).to include(environment: "test", server: nil)

    server = provider.create_server(
      spec: { name: config.server.name, region: config.server.region, size: config.server.size,
              image: config.server.image, ssh_key_id: "key", tags: config.server.tags }
    )
    store.update("test") do |state|
      state["resources"]["server"] = server.to_h.transform_keys(&:to_s)
      25.times { |index| state["operations"] << { "index" => index } }
      state
    end
    status = Kitsune::Kit::Workflows::InspectEnvironment.new(
      config: config, provider: provider, state_store: store
    ).call.value
    expect(status.to_h.dig(:server, :id)).to eq(server.id)
    expect(status.last_operations.length).to eq(20)
  end

  it "rolls back capable operations in reverse order and skips unmanaged ones" do
    calls = []
    operation = Struct.new(:resource, :changed, :calls) do
      def rollback
        calls << resource
        changed
      end
    end
    no_rollback = Struct.new(:resource).new("read-only")
    result = Kitsune::Kit::Workflows::Rollback.new(
      config: config,
      operations: [operation.new("first", true, calls), no_rollback, operation.new("last", false, calls)],
      event_bus: bus
    ).call

    expect(result).to be_success
    expect(result.value).to eq(["first"])
    expect(calls).to eq(%w[last first])
    expect(events.map(&:type)).to include("operation_started", "operation_succeeded", "run_finished")
  end

  it "emits a failed run and re-raises rollback failures" do
    failing = Struct.new(:resource) do
      def rollback = raise("rollback failed")
    end.new("bad")

    expect do
      Kitsune::Kit::Workflows::Rollback.new(config: config, operations: [failing], event_bus: bus).call
    end.to raise_error(RuntimeError, /rollback failed/)
    expect(events.last.data.fetch(:status)).to eq("failure")
  end
end
