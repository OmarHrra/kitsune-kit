# frozen_string_literal: true

RSpec.shared_examples "a provider adapter" do
  let(:contract_server_spec) do
    {
      name: "contract-test",
      region: "sfo3",
      size: "s-1vcpu-1gb",
      image: "ubuntu-24-04-x64",
      ssh_key_id: "123",
      tags: ["kitsune-managed"]
    }
  end

  it "validates credentials" do
    expect(provider.validate_credentials!).to be(true)
  end

  it "maps rejected credentials to the authentication error contract" do
    expect { unauthorized_provider.validate_credentials! }
      .to raise_error(Kitsune::Kit::Errors::AuthenticationError) do |error|
        expect(error.retryable).to be(false)
      end
  end

  it "validates the desired server configuration" do
    expect(provider.validate_server_spec!(spec: contract_server_spec)).to be(true)
  end

  it "creates, finds, waits for and deletes a server by provider ID" do
    created = provider.create_server(spec: contract_server_spec)
    ready = provider.wait_until_ready(id: created.id, timeout: 1)

    expect(ready.public_ip).not_to be_nil
    expect(provider.find_server(name: "contract-test", tags: ["kitsune-managed"]).id).to eq(created.id)
    expect(provider.find_server_by_id(id: created.id)).to eq(ready)
    expect(provider.delete_server(id: created.id)).to be(true)
    expect(provider.find_server(name: "contract-test", tags: ["kitsune-managed"])).to be_nil
  end

  it "maps an exhausted readiness wait to the timeout contract" do
    created = timeout_provider.create_server(spec: contract_server_spec)

    expect { timeout_provider.wait_until_ready(id: created.id, timeout: 0) }
      .to raise_error(Kitsune::Kit::Errors::TimeoutError)
  end

  it "upserts and removes DNS records by exact ID" do
    candidate = Kitsune::Kit::Adapters::DnsRecord.new(
      id: nil,
      zone: "example.test",
      name: "app",
      type: "A",
      data: "203.0.113.10",
      ttl: 300
    )
    saved = provider.upsert_dns_record(record: candidate)

    expect(provider.find_dns_record(zone: "example.test", name: "app", type: "A").id).to eq(saved.id)
    expect(provider.delete_dns_record(id: saved.id, zone: "example.test")).to be(true)
  end
end
