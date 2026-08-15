# frozen_string_literal: true

require "spec_helper"
require "kitsune/kit/adapters/confirming_host_key_verifier"

RSpec.describe Kitsune::Kit::Adapters::ConfirmingHostKeyVerifier do
  let(:host_keys_class) do
    Class.new do
      include Enumerable

      attr_reader :host, :added

      def initialize(host, keys = [])
        @host = host
        @keys = keys
      end

      def each(&) = @keys.each(&)
      def empty? = @keys.empty?

      def add_host_key(key)
        @added = key
        @keys << key
      end
    end
  end
  let(:host_keys) { host_keys_class.new("203.0.113.10") }
  let(:session) { Struct.new(:host_keys).new(host_keys) }
  let(:key) { Struct.new(:ssh_type).new("ssh-ed25519") }
  let(:arguments) { { session: session, key: key, fingerprint: "SHA256:verified" } }

  it "shows the exact fingerprint to the confirmation callback before remembering a new host" do
    confirmation = lambda do |host:, fingerprint:, key_type:|
      expect(host).to eq("203.0.113.10")
      expect(fingerprint).to eq("SHA256:verified")
      expect(key_type).to eq("ssh-ed25519")
      true
    end

    expect(described_class.new(&confirmation).verify(arguments)).to be(true)
    expect(host_keys.added).to be(key)
  end

  it "does not remember a host when the fingerprint is rejected" do
    verifier = described_class.new { |**| false }

    expect { verifier.verify(arguments) }.to raise_error(Net::SSH::HostKeyUnknown)
    expect(host_keys.added).to be_nil
  end

  it "accepts a previously stored matching key without asking again" do
    known_key = double(matches_key?: true)
    known_hosts = host_keys_class.new("203.0.113.10", [known_key])
    known_session = Struct.new(:host_keys).new(known_hosts)
    confirmation = proc { raise "confirmation should not run" }

    result = described_class.new(&confirmation).verify(arguments.merge(session: known_session))

    expect(result).to be(true)
  end
end
