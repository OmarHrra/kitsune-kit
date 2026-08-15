# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "spec_helper"
require "kitsune/kit/adapters/transport_factory"

RSpec.describe Kitsune::Kit::Operations::RemoteScript do
  let(:root) { Dir.mktmpdir("kitsune-remote") }
  let(:config) { build_config }
  let(:server) do
    Kitsune::Kit::Adapters::ServerRecord.new(
      id: "server-1",
      name: config.server.name,
      status: "active",
      public_ip: "203.0.113.10",
      region: config.server.region,
      size: config.server.size,
      image: config.server.image,
      tags: config.server.tags
    )
  end
  let(:transport) { Kitsune::Kit::Adapters::FakeTransport.new }
  let(:factory) do
    Kitsune::Kit::Adapters::FakeTransportFactory.new(transport: transport, server: server)
  end
  let(:store) { Kitsune::Kit::StateStore.new(root: root) }
  let(:script_path) { File.join(root, "operation.sh") }
  subject(:operation) do
    described_class.new(
      config: config,
      transport_factory: factory,
      state_store: store,
      resource: "test.operation",
      script_path: script_path,
      arguments: ["safe-value"]
    )
  end

  before { File.write(script_path, "#!/bin/sh\nexit 0\n") }
  after { FileUtils.remove_entry(root) }

  it "plans without mutating when the marker is absent" do
    change = operation.plan

    expect(change.action).to eq("create")
    expect(transport.uploads).to be_empty
  end

  it "uploads, applies, verifies and records a managed fingerprint" do
    change = operation.plan

    expect(operation.apply(change)).to be(true)

    expect(transport.uploads.keys.one?).to be(true)
    script_actions = transport.calls.filter_map do |name, arguments|
      next unless name == :execute && arguments[:command] == "sudo"

      arguments[:arguments]
    end
    expect(script_actions).to include(include("apply"), include("verify"))
    expect(store.read("test").dig("resources", "test.operation", "managed")).to be(true)
  end

  it "finalizes only after a fresh verification and verifies again afterward" do
    verifications = 0
    finalized = described_class.new(
      config: config,
      transport_factory: factory,
      state_store: store,
      resource: "ssh.policy",
      script_path: script_path,
      verification: { callback: -> { verifications += 1 }, finalize_action: "finalize" }
    )

    finalized.apply(finalized.plan)
    actions = transport.calls.filter_map do |name, arguments|
      next unless name == :execute && arguments[:command] == "sudo" && arguments[:arguments].first == "bash"

      arguments[:arguments][2]
    end
    expect(actions).to eq(%w[apply verify finalize verify_final])
    expect(verifications).to eq(2)
  end

  it "restores a safety-critical transition through the preserved session when fresh verification fails" do
    guarded = described_class.new(
      config: config,
      transport_factory: factory,
      state_store: store,
      resource: "ssh.policy",
      script_path: script_path,
      verification: {
        callback: -> { raise Kitsune::Kit::Errors::VerificationError, "fresh login failed" },
        finalize_action: "finalize",
        rollback_on_failure: true
      }
    )

    expect { guarded.apply(guarded.plan) }
      .to raise_error(Kitsune::Kit::Errors::VerificationError, /fresh login failed/)
    actions = transport.calls.filter_map do |name, arguments|
      next unless name == :execute && arguments[:command] == "sudo" && arguments[:arguments].first == "bash"

      arguments[:arguments][2]
    end
    expect(actions).to eq(%w[apply verify rollback])
    expect(store.read("test").dig("resources", "ssh.policy")).to be_nil
  end

  it "surfaces an actionable verification error when preserved-session recovery also fails" do
    guarded = described_class.new(
      config: config, transport_factory: factory, state_store: store, resource: "ssh.policy",
      script_path: script_path,
      verification: {
        callback: -> { raise Kitsune::Kit::Errors::VerificationError, "fresh login failed" },
        finalize_action: "finalize", rollback_on_failure: true
      }
    )
    allow(transport).to receive(:execute).and_wrap_original do |original, command, **arguments|
      if command == "sudo" && arguments.fetch(:arguments).include?("rollback")
        Kitsune::Kit::Adapters::CommandResult.new(stdout: "", stderr: "rollback denied", exit_status: 2,
                                                  duration_ms: 1)
      else
        original.call(command, **arguments)
      end
    end

    expect { guarded.apply(guarded.plan) }.to raise_error(Kitsune::Kit::Errors::VerificationError) { |error|
      expect(error.message).to include("preserved SSH session could not restore")
      expect(error.context).to include(
        original_error: "verification_error", recovery_error: "remote_command_error"
      )
    }
  end

  it "is unchanged when the remote marker matches" do
    fingerprint = operation.plan.details.fetch(:fingerprint)
    transport.stub(
      "sudo",
      arguments: ["cat", "/var/lib/kitsune/state/test-operation.sha256"],
      stdout: "#{fingerprint}\n"
    )

    expect(operation.plan.action).to eq("no_change")
  end

  it "does not rollback a resource absent from managed state" do
    expect(operation.rollback).to be(false)
    expect(transport.uploads).to be_empty
  end

  it "can use an explicit root transport for rollback" do
    root_transport = Kitsune::Kit::Adapters::FakeTransport.new
    role_factory = Kitsune::Kit::Adapters::FakeTransportFactory.new(
      transport: transport,
      server: server,
      deploy_transport: transport,
      root_transport: root_transport
    )
    role_operation = described_class.new(
      config: config,
      transport_factory: role_factory,
      state_store: store,
      resource: "user.deploy",
      script_path: script_path,
      transport_roles: { apply: :deploy, rollback: :root }
    )
    role_operation.apply(role_operation.plan)

    expect(role_operation.rollback).to be(true)
    expect(root_transport.uploads.keys).to include(match(/rollback/))
    rollback_call = root_transport.calls.find do |name, arguments|
      name == :execute && arguments[:arguments]&.include?("rollback")
    end
    expect(rollback_call).not_to be_nil
  end

  it "surfaces remote status and stderr" do
    allow(transport).to receive(:execute).and_wrap_original do |original, command, **arguments|
      if command == "sudo" && arguments.fetch(:arguments).include?("apply")
        Kitsune::Kit::Adapters::CommandResult.new(stdout: "", stderr: "failed", exit_status: 2, duration_ms: 1)
      else
        original.call(command, **arguments)
      end
    end

    expect { operation.apply(operation.plan) }
      .to raise_error(Kitsune::Kit::Errors::RemoteCommandError, /status 2/)
  end
end
