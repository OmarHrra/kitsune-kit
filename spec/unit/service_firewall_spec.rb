# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "spec_helper"

RSpec.describe Kitsune::Kit::Operations::ServiceFirewall do
  let(:root) { Dir.mktmpdir("kitsune-firewall") }
  let(:store) { Kitsune::Kit::StateStore.new(root: root) }
  let(:transport) { Kitsune::Kit::Adapters::FakeTransport.new }

  after { FileUtils.remove_entry(root) }

  def firewall(service)
    described_class.new(
      config: build_config(postgres: service.to_h), type: "postgres", service: service,
      transport: transport, state_store: store, resource: "service.postgres"
    )
  end

  def common(port)
    ["DOCKER-USER", "-p", "tcp", "-m", "conntrack", "--ctorigdstport", port.to_s, "--ctdir", "ORIGINAL"]
  end

  def allow_rule(port, cidr)
    [*common(port), "-s", cidr, "-m", "comment", "--comment", "kitsune:postgres:allow", "-j", "ACCEPT"]
  end

  def drop_rule(port)
    [*common(port), "-m", "comment", "--comment", "kitsune:postgres:drop", "-j", "DROP"]
  end

  def check_missing(rule) = transport.stub("sudo", arguments: ["iptables", "-C", *rule], exit_status: 1)

  it "removes every recorded published rule when the desired service becomes private" do
    service = build_service(type: :postgres, overrides: { publish: false })
    previous = {
      "published" => true, "port" => 5432, "firewall_rules_added" => ["203.0.113.1/32"],
      "firewall_drop_added" => true
    }

    expect(firewall(service).reconcile(previous)).to be_nil
    deleted = transport.calls.select { |name, data| name == :execute && data[:arguments].include?("-D") }
    expect(deleted.length).to eq(2)
  end

  it "retains currently owned rules without claiming pre-existing rules" do
    cidr = "203.0.113.1/32"
    service = build_service(
      type: :postgres,
      overrides: { publish: true, bind: "0.0.0.0", allowed_cidrs: [cidr] }
    )
    previous = {
      "published" => true, "port" => 5432, "firewall_rules_added" => [cidr],
      "firewall_drop_added" => true
    }
    managed = firewall(service)

    managed.reconcile(previous)

    expect(managed.owned_rules).to eq([cidr])
    expect(managed.drop_owned).to be(true)
    expect(transport.calls.none? { |_name, data| data[:arguments]&.include?("-I") }).to be(true)
  end

  it "adds the new route before removing stale CIDR and port rules" do
    new_cidr = "198.51.100.2/32"
    service = build_service(
      type: :postgres,
      overrides: { publish: true, bind: "0.0.0.0", port: 5544, allowed_cidrs: [new_cidr] }
    )
    previous = {
      "published" => true, "port" => 5432, "firewall_rules_added" => ["203.0.113.1/32"],
      "firewall_drop_added" => true
    }
    check_missing(drop_rule(5544))
    check_missing(allow_rule(5544, new_cidr))
    managed = firewall(service)

    managed.reconcile(previous)

    mutations = transport.calls.filter_map do |name, data|
      next unless name == :execute && Array(data[:arguments]).intersect?(%w[-I -D])

      data[:arguments]
    end
    expect(mutations.first(2)).to all(include("-I"))
    expect(mutations.last(2)).to all(include("-D"))
    expect(managed.owned_rules).to eq([new_cidr])
    expect(managed.drop_owned).to be(true)
  end

  it "restores missing previous rules and ignores a previous private service" do
    service = build_service(type: :postgres, overrides: { publish: false })
    managed = firewall(service)
    expect(managed.restore("published" => false)).to be_nil

    cidr = "203.0.113.1/32"
    check_missing(drop_rule(5432))
    check_missing(allow_rule(5432, cidr))
    managed.restore(
      "published" => true, "port" => 5432, "firewall_rules_added" => [cidr]
    )
    additions = transport.calls.count { |name, data| name == :execute && data[:arguments]&.include?("-I") }
    expect(additions).to eq(2)
  end

  it "tolerates absent owned rules but raises typed errors for real iptables failures" do
    service = build_service(type: :postgres, overrides: { publish: false })
    cidr = "203.0.113.1/32"
    previous = {
      "published" => true, "port" => 5432, "firewall_rules_added" => [cidr],
      "firewall_drop_added" => false
    }
    transport.stub("sudo", arguments: ["iptables", "-D", *allow_rule(5432, cidr)], exit_status: 1)
    expect(firewall(service).reconcile(previous)).to be_nil

    transport.stub(
      "sudo", arguments: ["iptables", "-D", *allow_rule(5432, cidr)], stderr: "denied", exit_status: 2
    )
    expect { firewall(service).reconcile(previous) }
      .to raise_error(Kitsune::Kit::Errors::RemoteCommandError, /remove Docker firewall rule/)
  end

  it "raises a typed error when a new rule cannot be added" do
    cidr = "203.0.113.1/32"
    service = build_service(
      type: :postgres,
      overrides: { publish: true, bind: "0.0.0.0", allowed_cidrs: [cidr] }
    )
    check_missing(drop_rule(5432))
    transport.stub(
      "sudo", arguments: ["iptables", "-I", "DOCKER-USER", "1", *drop_rule(5432).drop(1)],
              stderr: "denied", exit_status: 2
    )

    expect { firewall(service).reconcile(nil) }
      .to raise_error(Kitsune::Kit::Errors::RemoteCommandError, /add Docker firewall rule/)
  end

  it "removes newly added rules and restores deleted old rules when reconciliation fails" do
    old_cidr = "203.0.113.1/32"
    new_cidr = "198.51.100.2/32"
    service = build_service(
      type: :postgres,
      overrides: { publish: true, bind: "0.0.0.0", port: 5544, allowed_cidrs: [new_cidr] }
    )
    previous = {
      "published" => true, "port" => 5432, "firewall_rules_added" => [old_cidr],
      "firewall_drop_added" => true
    }
    check_missing(drop_rule(5544))
    check_missing(allow_rule(5544, new_cidr))
    transport.stub("sudo", arguments: ["iptables", "-D", *allow_rule(5432, old_cidr)])
    transport.stub(
      "sudo", arguments: ["iptables", "-D", *drop_rule(5432)], stderr: "denied", exit_status: 2
    )
    check_missing(allow_rule(5432, old_cidr))

    expect { firewall(service).reconcile(previous) }
      .to raise_error(Kitsune::Kit::Errors::RemoteCommandError, /remove Docker firewall rule/)

    cleanup_deletes = transport.calls.select do |name, data|
      name == :execute && data[:arguments]&.include?("-D") && data[:arguments].include?("5544")
    end
    restored_old = transport.calls.find do |name, data|
      name == :execute && data[:arguments]&.include?("-I") && data[:arguments].include?(old_cidr)
    end
    expect(cleanup_deletes.length).to be >= 2
    expect(restored_old).not_to be_nil
  end

  it "surfaces both failures when firewall reconciliation cannot recover" do
    cidr = "198.51.100.2/32"
    service = build_service(
      type: :postgres, overrides: { publish: true, bind: "0.0.0.0", allowed_cidrs: [cidr] }
    )
    check_missing(drop_rule(5432))
    check_missing(allow_rule(5432, cidr))
    mutation = 0
    allow(transport).to receive(:execute).and_wrap_original do |original, command, **arguments|
      args = arguments.fetch(:arguments)
      if command == "sudo" && args.include?("iptables") && Array(args).intersect?(%w[-I -D])
        mutation += 1
        if mutation >= 2
          next Kitsune::Kit::Adapters::CommandResult.new(
            stdout: "", stderr: "firewall denied", exit_status: 2, duration_ms: 1
          )
        end
      end
      original.call(command, **arguments)
    end

    expect { firewall(service).reconcile(nil) }
      .to raise_error(Kitsune::Kit::Errors::VerificationError) { |error|
        expect(error.message).to include("reconciliation and recovery both failed")
        expect(error.context).to include(
          original_error: "remote_command_error", recovery_error: "remote_command_error"
        )
      }
  end
end
