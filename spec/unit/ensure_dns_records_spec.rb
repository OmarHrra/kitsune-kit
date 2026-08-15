# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "spec_helper"

RSpec.describe Kitsune::Kit::Operations::EnsureDnsRecords do
  let(:root) { Dir.mktmpdir("kitsune-dns") }
  let(:base_config) { build_config }
  let(:config) { base_config.with(dns: Kitsune::Kit::Configuration::Dns.new(domains: domains, ttl: 300)) }
  let(:domains) { ["app.example.co.uk", "example.com"] }
  let(:server) do
    Kitsune::Kit::Adapters::ServerRecord.new(
      id: "server-1",
      name: config.server.name,
      status: "active",
      public_ip: "203.0.113.20",
      region: config.server.region,
      size: config.server.size,
      image: config.server.image,
      tags: config.server.tags
    )
  end
  let(:provider) { Kitsune::Kit::Adapters::FakeProvider.new(servers: [server]) }
  let(:store) { Kitsune::Kit::StateStore.new(root: root) }
  subject(:operation) { described_class.new(config: config, provider: provider, state_store: store) }

  after { FileUtils.remove_entry(root) }

  it "uses the public suffix list for compound domain suffixes" do
    records = operation.plan.details.fetch(:records)

    expect(records.first).to include(zone: "example.co.uk", name: "app")
    expect(records.last).to include(zone: "example.com", name: "@")
  end

  it "creates exact records and stores IDs and prior values" do
    operation.apply(operation.plan)

    expect(provider.dns_records.map(&:data)).to all(eq("203.0.113.20"))
    state = store.read("test").dig("resources", "dns", "app.example.co.uk")
    expect(state.dig("record", "id")).not_to be_nil
    expect(state["previous"]).to be_nil
  end

  it "updates an existing record and preserves its previous value for rollback" do
    provider.upsert_dns_record(
      record: Kitsune::Kit::Adapters::DnsRecord.new(
        id: nil, zone: "example.com", name: "@", type: "A", data: "198.51.100.1", ttl: 300
      )
    )

    operation.apply(operation.plan)

    previous = store.read("test").dig("resources", "dns", "example.com", "previous")
    expect(previous).to include("data" => "198.51.100.1")
  end

  it "is unchanged when every exact record matches" do
    operation.apply(operation.plan)

    expect(operation.plan.action).to eq("no_change")
  end

  it "can plan before the dependent server exists" do
    empty_provider = Kitsune::Kit::Adapters::FakeProvider.new
    pending = described_class.new(config: config, provider: empty_provider, state_store: store).plan

    expect(pending.details).to include(depends_on: "server")
    expect(pending.details.fetch(:records).first.dig(:desired, :data)).to eq("pending-server-ip")
  end

  it "persists each record immediately and safely resumes after a partial provider failure" do
    fail_second = true
    allow(provider).to receive(:upsert_dns_record).and_wrap_original do |original, record:|
      raise Kitsune::Kit::Errors::ProviderError, "temporary DNS failure" if fail_second && record.name == "@"

      original.call(record: record)
    end

    expect { operation.apply(operation.plan) }.to raise_error(Kitsune::Kit::Errors::ProviderError)
    managed = store.read("test").dig("resources", "dns")
    expect(managed.keys).to eq(["app.example.co.uk"])

    fail_second = false
    expect(operation.apply(operation.plan).length).to eq(2)
    expect(provider.dns_records.length).to eq(2)
    expect(operation.rollback).to be(true)
    expect(provider.dns_records).to be_empty
  end
end
