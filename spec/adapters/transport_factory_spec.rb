# frozen_string_literal: true

require "spec_helper"
require "kitsune/kit/adapters/transport_factory"

RSpec.describe Kitsune::Kit::Adapters::TransportFactory do
  let(:config) { build_config }
  let(:provider) { Kitsune::Kit::Adapters::FakeProvider.new }
  let(:deploy) { instance_double(Kitsune::Kit::Adapters::NetSshTransport, reachable?: false) }
  let(:root_transport) { instance_double(Kitsune::Kit::Adapters::NetSshTransport) }
  let(:time) { { value: 0.0 } }
  let(:sleeps) { [] }
  let(:clock) { -> { time[:value] } }
  let(:sleeper) do
    recorded_sleeps = sleeps
    monotonic_time = time
    Class.new do
      define_method(:sleep) do |seconds|
        recorded_sleeps << seconds
        monotonic_time[:value] += seconds
      end
    end.new
  end
  let(:factory) do
    described_class.new(
      config: config,
      provider: provider,
      sleeper: sleeper,
      monotonic_clock: clock,
      bootstrap_timeout: 10
    )
  end

  before do
    allow(factory).to receive_messages(deploy: deploy, root: root_transport)
  end

  it "waits for root SSH after a new server becomes active" do
    allow(root_transport).to receive(:reachable?).and_return(false, true)

    expect(factory.wait_for_bootstrap).to be(root_transport)
    expect(sleeps).to eq([5])
  end

  it "returns the deploy transport immediately when resuming a configured server" do
    allow(deploy).to receive(:reachable?).and_return(true)

    expect(factory.wait_for_bootstrap).to be(deploy)
    expect(sleeps).to be_empty
  end

  it "fails with an actionable bounded error when neither login becomes reachable" do
    allow(root_transport).to receive(:reachable?).and_return(false)

    expect { factory.wait_for_bootstrap }
      .to raise_error(Kitsune::Kit::Errors::ConnectionError, /within 10 seconds/) { |error|
        expect(error.retryable).to be(true)
        expect(error.hint).to include("uploaded public key")
      }
    expect(sleeps).to eq([5, 5])
  end

  it "keeps the immediate bootstrap check available for doctor" do
    allow(root_transport).to receive(:reachable?).and_return(false)

    expect { factory.bootstrap }
      .to raise_error(Kitsune::Kit::Errors::ConnectionError, /neither deploy nor root/)
    expect(sleeps).to be_empty
  end
end
