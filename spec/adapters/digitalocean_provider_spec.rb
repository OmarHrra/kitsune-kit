# frozen_string_literal: true

require "spec_helper"
require_relative "../contracts/provider_contract"

module DigitalOceanFixtures
  Network = Struct.new(:type, :ip_address, keyword_init: true)
  Networks = Struct.new(:v4, keyword_init: true)
  Domain = Struct.new(:id, :name, :type, :data, :ttl, keyword_init: true)
  Region = Struct.new(:slug, :available, :sizes, keyword_init: true)
  Size = Struct.new(:slug, :available, :regions, keyword_init: true)
  Image = Struct.new(:slug, :regions, keyword_init: true)

  class Droplet
    attr_accessor :id, :name, :status, :networks, :region, :size_slug, :size, :image, :tags

    def initialize(**attributes)
      attributes.each { |name, value| public_send("#{name}=", value) }
    end
  end

  class Endpoint
    attr_reader :items, :deleted

    def initialize(items = [])
      @items = items
      @deleted = []
    end

    def all(**) = items
    def info = true
    def find(id:) = items.find { |item| item.id.to_s == id.to_s } || raise("not found")

    def create(value, **)
      if value.is_a?(DropletKit::Droplet)
        saved = Droplet.new(
          id: "droplet-1", name: value.name, status: "new", networks: Networks.new(v4: []), region: value.region,
          size_slug: value.size, image: value.image, tags: value.tags
        )
      else
        saved = Domain.new(id: "record-1", name: value.name, type: value.type, data: value.data, ttl: value.ttl)
      end
      items << saved
      saved
    end

    def update(value, id:, **)
      saved = Domain.new(id: id.to_s, name: value.name, type: value.type, data: value.data, ttl: value.ttl)
      items.map! { |item| item.id.to_s == id.to_s ? saved : item }
      saved
    end

    def delete(id:, **)
      @deleted << id.to_s
      items.reject! { |item| item.id.to_s == id.to_s }
      true
    end
  end

  Client = Struct.new(:account, :droplets, :domain_records, :regions, :sizes, :images, keyword_init: true)
end

RSpec.describe Kitsune::Kit::Adapters::DigitalOceanProvider do
  let(:droplets) { DigitalOceanFixtures::Endpoint.new }
  let(:records) { DigitalOceanFixtures::Endpoint.new }
  let(:account) { DigitalOceanFixtures::Endpoint.new }
  let(:regions) do
    values = [DigitalOceanFixtures::Region.new(
      slug: "sfo3", available: true, sizes: ["s-1vcpu-1gb"]
    )]
    DigitalOceanFixtures::Endpoint.new(values)
  end
  let(:sizes) do
    values = [DigitalOceanFixtures::Size.new(
      slug: "s-1vcpu-1gb", available: true, regions: ["sfo3"]
    )]
    DigitalOceanFixtures::Endpoint.new(values)
  end
  let(:images) do
    values = [DigitalOceanFixtures::Image.new(slug: "ubuntu-24-04-x64", regions: ["sfo3"])]
    DigitalOceanFixtures::Endpoint.new(values)
  end
  let(:client) do
    DigitalOceanFixtures::Client.new(
      account: account, droplets: droplets, domain_records: records, regions: regions, sizes: sizes, images: images
    )
  end
  let(:sleeper) { class_double(Kernel, sleep: nil) }
  let(:server_spec) do
    {
      name: "contract-test", region: "sfo3", size: "s-1vcpu-1gb", image: "ubuntu-24-04-x64",
      ssh_key_id: "123", tags: ["kitsune-managed"]
    }
  end
  subject(:provider) { described_class.new(token: "token", client: client, sleeper: sleeper) }

  context "when exercised through the shared provider contract" do
    let(:unauthorized_provider) do
      invalid_account = DigitalOceanFixtures::Endpoint.new
      allow(invalid_account).to receive(:info).and_raise(SocketError)
      invalid_client = DigitalOceanFixtures::Client.new(
        account: invalid_account, droplets: DigitalOceanFixtures::Endpoint.new,
        domain_records: DigitalOceanFixtures::Endpoint.new, regions: regions, sizes: sizes, images: images
      )
      described_class.new(token: "bad-token", client: invalid_client, sleeper: sleeper)
    end
    let(:timeout_provider) do
      timeout_client = DigitalOceanFixtures::Client.new(
        account: DigitalOceanFixtures::Endpoint.new, droplets: DigitalOceanFixtures::Endpoint.new,
        domain_records: DigitalOceanFixtures::Endpoint.new, regions: regions, sizes: sizes, images: images
      )
      described_class.new(token: "token", client: timeout_client, sleeper: sleeper)
    end

    before do
      allow(droplets).to receive(:find).and_wrap_original do |method, id:|
        droplet = method.call(id: id)
        droplet.status = "active"
        droplet.networks = DigitalOceanFixtures::Networks.new(
          v4: [DigitalOceanFixtures::Network.new(type: "public", ip_address: "203.0.113.10")]
        )
        droplet
      end
    end

    it_behaves_like "a provider adapter"
  end

  it "creates, finds and deletes exact tagged servers through DropletKit" do
    created = provider.create_server(
      spec: { name: "web", region: "sfo3", size: "s-1vcpu-1gb", image: "ubuntu-24-04-x64",
              ssh_key_id: "123", tags: ["kitsune-managed"] }
    )
    ready_droplet = droplets.items.first
    ready_droplet.status = "active"
    ready_droplet.networks = DigitalOceanFixtures::Networks.new(
      v4: [DigitalOceanFixtures::Network.new(type: "public", ip_address: "203.0.113.10")]
    )

    expect(provider.wait_until_ready(id: created.id, timeout: 1).public_ip).to eq("203.0.113.10")
    expect(provider.find_server(name: "web", tags: ["kitsune-managed"]).id).to eq("droplet-1")
    expect(provider.find_server_by_id(id: "droplet-1").name).to eq("web")
    expect(provider.delete_server(id: "droplet-1")).to be(true)
  end

  it "validates region, size and image availability before creation" do
    expect(provider.validate_server_spec!(spec: server_spec)).to be(true)

    invalid = server_spec.merge(region: "moon-1")
    expect { provider.validate_server_spec!(spec: invalid) }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /region is unavailable/)
  end

  it "does not adopt a same-name server missing the configured tags" do
    droplets.items << DigitalOceanFixtures::Droplet.new(
      id: "other", name: "web", status: "active", networks: DigitalOceanFixtures::Networks.new(v4: []), region: "sfo3",
      size_slug: "s-1vcpu-1gb", image: "ubuntu-24-04-x64", tags: ["unmanaged"]
    )

    expect(provider.find_server(name: "web", tags: ["kitsune-managed"])).to be_nil
  end

  it "creates, updates and deletes DNS records by exact ID" do
    candidate = Kitsune::Kit::Adapters::DnsRecord.new(
      id: nil, zone: "example.com", name: "app", type: "A", data: "203.0.113.10", ttl: 300
    )
    saved = provider.upsert_dns_record(record: candidate)
    updated = provider.upsert_dns_record(record: saved.with(data: "203.0.113.11"))

    expect(provider.find_dns_record(zone: "example.com", name: "app", type: "A").data).to eq("203.0.113.11")
    expect(updated.id).to eq(saved.id)
    expect(provider.delete_dns_record(id: saved.id, zone: "example.com")).to be(true)
  end

  it "maps authentication and provider failures to stable domain errors" do
    allow(account).to receive(:info).and_raise(SocketError)
    expect { provider.validate_credentials! }
      .to raise_error(Kitsune::Kit::Errors::AuthenticationError) { |error|
        expect(error.retryable).to be(false)
        expect(error.hint).to include("account:read")
      }

    allow(droplets).to receive(:all).and_raise(Timeout::Error)
    expect { provider.find_server(name: "web") }
      .to raise_error(Kitsune::Kit::Errors::ProviderError) { |error| expect(error.retryable).to be(true) }
  end

  it "uses DropletKit's real account endpoint method" do
    expect(provider.validate_credentials!).to be(true)
    expect(account).to respond_to(:info)
    expect(account).not_to respond_to(:get)
  end

  it "times out while waiting without hiding the actionable timeout" do
    droplets.items << DigitalOceanFixtures::Droplet.new(
      id: "slow", name: "web", status: "new", networks: DigitalOceanFixtures::Networks.new(v4: []), region: "sfo3",
      size_slug: "small", image: "ubuntu-24-04-x64", tags: []
    )

    expect { provider.wait_until_ready(id: "slow", timeout: 0) }
      .to raise_error(Kitsune::Kit::Errors::TimeoutError, /did not become ready/)
  end

  it "rejects a missing token before constructing a client" do
    expect { described_class.new(token: "") }
      .to raise_error(Kitsune::Kit::Errors::AuthenticationError, /token is missing/)
  end

  it "applies the configured deadline to every SDK HTTP request" do
    limited = described_class.new(token: "token", maximum_timeout: 7.5)
    client = limited.instance_variable_get(:@client)

    expect(client.open_timeout).to eq(7.5)
    expect(client.timeout).to eq(7.5)
    expect { described_class.new(token: "token", maximum_timeout: 0) }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /greater than zero/)
  end
end
