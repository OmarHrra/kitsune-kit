# frozen_string_literal: true

require "base64"
require "shellwords"
require "spec_helper"
require_relative "../contracts/transport_contract"

module NetSshFixtures
  ExitData = Struct.new(:value) do
    def read_long = value
  end

  class Channel
    attr_reader :command, :stdin

    def initialize(stdout: "output", stderr: "warning", status: 0)
      @stdout = stdout
      @stderr = stderr
      @status = status
    end

    def exec(command)
      @command = command
      yield self, true
    end

    def send_data(value) = @stdin = value
    def eof! = true
    def on_data(&block) = @on_data = block
    def on_extended_data(&block) = @on_extended_data = block
    def on_request(_name, &block) = @on_request = block

    def fire
      @on_data&.call(self, @stdout)
      @on_extended_data&.call(self, 1, @stderr)
      @on_request&.call(self, ExitData.new(@status))
    end
  end

  class Session
    attr_reader :channel

    def initialize(channel)
      @channel = channel
    end

    def open_channel = yield(channel)
    def loop = channel.fire
  end
end

RSpec.describe Kitsune::Kit::Adapters::NetSshTransport do
  let(:channel) { NetSshFixtures::Channel.new }
  let(:session) { NetSshFixtures::Session.new(channel) }
  subject(:transport) do
    described_class.new(host: "203.0.113.10", user: "deploy", port: 22, key_path: "/tmp/test-key",
                        known_hosts: "/tmp/known-hosts")
  end

  before do
    allow(Net::SSH).to receive(:start).and_yield(session)
  end

  context "when exercised through the shared transport contract" do
    let(:channel) { NetSshFixtures::Channel.new(stdout: "safe-value", stderr: "") }
    let(:unreachable_transport) do
      described_class.new(host: "203.0.113.10", user: "deploy", port: 22, key_path: "/tmp/key").tap do |value|
        allow(value).to receive(:with_connection).and_raise(
          Kitsune::Kit::Errors::ConnectionError.new("unreachable")
        )
      end
    end
    let(:timeout_transport) do
      described_class.new(
        host: "203.0.113.10", user: "deploy", port: 22, key_path: "/tmp/key", maximum_timeout: 0.001
      ).tap { |value| allow(value).to receive(:with_connection) { sleep(0.02) } }
    end

    it_behaves_like "a transport adapter"
  end

  it "escapes every argument and returns separated output, status and timing" do
    arguments = ["safe value", "; touch /tmp/owned", "$(id)"]
    result = transport.execute("printf", arguments: arguments)

    expect(channel.command).to eq(Shellwords.join(["printf", *arguments]))
    expect(result).to be_success
    expect(result.stdout).to eq("output")
    expect(result.stderr).to eq("warning")
    expect(result.duration_ms).to be_a(Integer)
  end

  it "uploads base64 content without interpolating content into the command" do
    content = "secret\n$(touch /tmp/owned)"

    expect(transport.upload(content: content, remote_path: "/tmp/safe-file", mode: "0600")).to be(true)
    expect(channel.stdin).to eq(Base64.strict_encode64(content))
    expect(channel.command).to include("kitsune-upload", "/tmp/safe-file", "0600")
    expect(channel.command).not_to include("secret", "touch /tmp/owned")
  end

  it "rejects unsafe commands, paths and modes before opening SSH" do
    expect { transport.execute("printf;id") }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /command/)
    expect { transport.upload(content: "x", remote_path: "/tmp/../etc/passwd") }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /path/)
    expect { transport.upload(content: "x", remote_path: "/tmp/file", mode: "777") }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /mode/)
    expect(Net::SSH).not_to have_received(:start)
  end

  it "maps SSH failures and reachability without leaking the original message" do
    allow(Net::SSH).to receive(:start).and_raise(Net::SSH::AuthenticationFailed, "private detail")

    expect(transport.reachable?).to be(false)
    expect { transport.execute("true") }
      .to raise_error(Kitsune::Kit::Errors::ConnectionError) do |error|
        expect(error.context).to eq(cause: "Net::SSH::AuthenticationFailed")
        expect(error.message).not_to include("private detail")
      end
  end

  it "enforces the configured maximum timeout" do
    limited = described_class.new(host: "203.0.113.10", user: "deploy", port: 22, key_path: "/tmp/key",
                                  maximum_timeout: 0.001)
    allow(limited).to receive(:with_connection) { sleep(0.02) }

    expect { limited.execute("true", timeout: 30) }
      .to raise_error(Kitsune::Kit::Errors::TimeoutError, /0.001 seconds/)
  end

  it "raises a typed remote error for a failed upload" do
    failing_channel = NetSshFixtures::Channel.new(status: 7)
    allow(Net::SSH).to receive(:start).and_yield(NetSshFixtures::Session.new(failing_channel))

    expect { transport.upload(content: "x", remote_path: "/tmp/file") }
      .to raise_error(Kitsune::Kit::Errors::RemoteCommandError, /status 7/)
  end

  it "reuses one verified SSH session for a multi-step transition" do
    transport.with_session do
      transport.execute("true")
      transport.execute("true")
    end

    expect(Net::SSH).to have_received(:start).once
  end
end
