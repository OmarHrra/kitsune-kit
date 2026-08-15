# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "yaml"
require "spec_helper"
require "kitsune/kit/adapters/transport_factory"

RSpec.describe Kitsune::Kit::Operations::EnsureService do
  let(:root) { Dir.mktmpdir("kitsune-service") }
  let(:secret) { "complex # password with spaces" }
  let(:config) { build_config(postgres: { enabled: true }) }
  let(:server) do
    Kitsune::Kit::Adapters::ServerRecord.new(
      id: "server-1", name: config.server.name, status: "active", public_ip: "203.0.113.10",
      region: config.server.region, size: config.server.size, image: config.server.image, tags: config.server.tags
    )
  end
  let(:transport) { Kitsune::Kit::Adapters::FakeTransport.new }
  let(:factory) { Kitsune::Kit::Adapters::FakeTransportFactory.new(transport: transport, server: server) }
  let(:store) { Kitsune::Kit::StateStore.new(root: root) }
  let(:secrets) { Kitsune::Kit::SecretStores::Environment.new(env: { "POSTGRES_PASSWORD" => secret }) }
  subject(:operation) do
    described_class.new(
      config: config,
      type: :postgres,
      transport_factory: factory,
      state_store: store,
      secret_store: secrets
    )
  end

  before do
    allow(transport).to receive(:execute).and_wrap_original do |original, command, **arguments|
      if command == "docker" && arguments.fetch(:arguments).include?("ps")
        Kitsune::Kit::Adapters::CommandResult.new(stdout: "container-id\n", stderr: "", exit_status: 0, duration_ms: 1)
      else
        original.call(command, **arguments)
      end
    end
  end

  after { FileUtils.remove_entry(root) }

  it "generates valid Compose YAML without publishing a port by default" do
    operation.apply(operation.plan)
    compose = transport.uploads.fetch("/home/deploy/.local/share/kitsune/services/postgres/compose.yml")[:content]

    parsed = YAML.safe_load(compose)
    expect(parsed.dig("services", "postgres")).not_to have_key("ports")
    expect(parsed.dig("networks", "private")).to include("external" => true, "name" => "kitsune-private")
  end

  it "uploads overlays and passes every Compose file to Docker in order" do
    overlay = File.join(root, "postgres.override.yml")
    File.write(overlay, "services:\n  postgres:\n    environment:\n      LOG_STATEMENTS: all\n")
    overlay_config = build_config(
      postgres: { enabled: true, compose: { mode: "overlay", file: overlay, allow_unsafe: false } }
    )
    layered = described_class.new(
      config: overlay_config, type: :postgres, transport_factory: factory, state_store: store, secret_store: secrets
    )

    layered.apply(layered.plan)

    expect(transport.uploads).to include(
      "/home/deploy/.local/share/kitsune/services/postgres/compose.yml",
      "/home/deploy/.local/share/kitsune/services/postgres/compose.override.yml"
    )
    config_call = transport.calls.find do |name, arguments|
      name == :execute && arguments[:command] == "docker" && arguments[:arguments].include?("config")
    end
    expect(config_call.last.fetch(:arguments)).to include(
      "--file", "/home/deploy/.local/share/kitsune/services/postgres/compose.yml",
      "--file", "/home/deploy/.local/share/kitsune/services/postgres/compose.override.yml"
    )
    expect(store.read("test").dig("resources", "service.postgres", "compose_mode")).to eq("overlay")
  end

  it "keeps the Redis password out of the resolved container command and process arguments" do
    redis_config = build_config(redis: { enabled: true })
    compose = Kitsune::Kit::ServiceCompose.new(
      config: redis_config, type: "redis", service: redis_config.services.redis
    ).content
    document = YAML.safe_load(compose)
    definition = document.dig("services", "redis")

    expect(definition.fetch("command").join(" ")).to include("$$REDIS_PASSWORD")
    expect(definition.dig("healthcheck", "test").join(" ")).to include("REDISCLI_AUTH", "$${REDIS_PASSWORD}")
    expect(definition.dig("healthcheck", "test").join(" ")).not_to include("redis-cli -a")
  end

  it "stores the secret only in the restricted remote env file" do
    operation.apply(operation.plan)
    env_file = transport.uploads.fetch("/home/deploy/.local/share/kitsune/services/postgres/.env")
    serialized_state = JSON.generate(store.read("test"))

    expect(env_file[:content]).to include(JSON.generate(secret))
    expect(env_file[:mode]).to eq("0600")
    expect(serialized_state).not_to include(secret)
  end

  it "uses a configured secret variable name consistently in env and Compose" do
    custom_config = build_config(
      postgres: { enabled: true, password_env: "MY_DATABASE_PASSWORD" }
    )
    custom = described_class.new(
      config: custom_config,
      type: :postgres,
      transport_factory: factory,
      state_store: store,
      secret_store: Kitsune::Kit::SecretStores::Environment.new(env: { "MY_DATABASE_PASSWORD" => secret })
    )

    custom.apply(custom.plan)
    compose = YAML.safe_load(
      transport.uploads.fetch("/home/deploy/.local/share/kitsune/services/postgres/compose.yml")[:content]
    )
    env_file = transport.uploads.fetch("/home/deploy/.local/share/kitsune/services/postgres/.env")[:content]

    expect(compose.dig("services", "postgres", "environment", "POSTGRES_PASSWORD"))
      .to eq("${MY_DATABASE_PASSWORD}")
    expect(env_file).to start_with("MY_DATABASE_PASSWORD=")
  end

  it "changes the fingerprint when the secret changes without exposing either secret" do
    first = operation.plan.details.fetch(:fingerprint)
    other = described_class.new(
      config: config,
      type: :postgres,
      transport_factory: factory,
      state_store: store,
      secret_store: Kitsune::Kit::SecretStores::Environment.new(env: { "POSTGRES_PASSWORD" => "other-secret" })
    ).plan

    expect(other.details.fetch(:fingerprint)).not_to eq(first)
    expect(other.details.to_s).not_to include(secret, "other-secret")
  end

  it "is a no-op when the remote marker already has the desired fingerprint" do
    first_change = operation.plan
    operation.apply(first_change)
    transport.stub(
      "sudo",
      arguments: ["cat", "/var/lib/kitsune/state/service-postgres.sha256"],
      stdout: "#{first_change.details.fetch(:fingerprint)}\n"
    )
    uploads_before = transport.uploads.dup

    second_change = operation.plan

    expect(second_change.action).to eq("no_change")
    expect(operation.apply(second_change)).to be(true)
    expect(transport.uploads).to eq(uploads_before)
  end

  it "removes containers without volumes and destroys data only through the explicit method" do
    operation.apply(operation.plan)

    expect(operation.remove).to be(true)
    remove_call = transport.calls.reverse.find do |name, arguments|
      name == :execute && arguments[:command] == "docker" && arguments[:arguments].include?("down")
    end
    expect(remove_call.last[:arguments]).not_to include("--volumes")
    expect(store.read("test").dig("resources", "service.postgres", "installed")).to be(false)
    expect(operation.plan.action).to eq("create")

    expect(operation.destroy_data).to be(true)
    destroy_call = transport.calls.reverse.find do |name, arguments|
      name == :execute && arguments[:command] == "docker" && arguments[:arguments].include?("down")
    end
    expect(destroy_call.last[:arguments]).to include("--volumes")
    expect(store.read("test").dig("resources", "service.postgres")).to be_nil
  end

  it "creates a restricted volume backup while the service is paused and always resumes it" do
    clock = -> { Time.utc(2026, 8, 13, 12, 34, 56) }
    backed_up = described_class.new(
      config: config,
      type: :postgres,
      transport_factory: factory,
      state_store: store,
      secret_store: secrets,
      clock: clock
    )
    backed_up.apply(backed_up.plan)

    path = backed_up.backup

    expect(path).to end_with("postgres-20260813T123456.tar.gz")
    calls = transport.calls.select { |name, arguments| name == :execute && arguments[:command] == "docker" }
    expect(calls.map { |_name, arguments| arguments[:arguments] }).to include(
      include("pause"), include(Kitsune::Kit::Operations::ServiceBackup::BACKUP_IMAGE, "tar", "-czf"),
      include("unpause")
    )
    chmod = transport.calls.find do |name, arguments|
      name == :execute && arguments[:command] == "chmod" && arguments[:arguments] == ["0600", path]
    end
    expect(chmod).not_to be_nil
  end

  it "unpauses the service when a backup command fails" do
    operation.apply(operation.plan)
    allow(transport).to receive(:execute).and_wrap_original do |original, command, **arguments|
      if command == "docker" && arguments.fetch(:arguments).include?(
        Kitsune::Kit::Operations::ServiceBackup::BACKUP_IMAGE
      )
        Kitsune::Kit::Adapters::CommandResult.new(stdout: "", stderr: "disk full", exit_status: 1, duration_ms: 1)
      else
        original.call(command, **arguments)
      end
    end

    expect { operation.backup }.to raise_error(Kitsune::Kit::Errors::RemoteCommandError, /back up/)
    unpause = transport.calls.reverse.find do |name, arguments|
      name == :execute && arguments[:command] == "docker" && arguments[:arguments].include?("unpause")
    end
    expect(unpause).not_to be_nil
  end

  it "rejects secrets containing newlines before uploading" do
    unsafe = described_class.new(
      config: config,
      type: :postgres,
      transport_factory: factory,
      state_store: store,
      secret_store: Kitsune::Kit::SecretStores::Environment.new(env: { "POSTGRES_PASSWORD" => "bad\nINJECTED=true" })
    )

    expect { unsafe.plan }.to raise_error(Kitsune::Kit::Errors::ConfigurationError, /control characters/)
    expect(transport.uploads).to be_empty
  end

  it "cleans up a failed first install so the next apply can resume" do
    fail_once = true
    allow(transport).to receive(:execute).and_wrap_original do |original, command, **arguments|
      if fail_once && command == "docker" && arguments.fetch(:arguments).include?("config")
        fail_once = false
        Kitsune::Kit::Adapters::CommandResult.new(stdout: "", stderr: "invalid", exit_status: 1, duration_ms: 1)
      elsif command == "docker" && arguments.fetch(:arguments).include?("ps")
        Kitsune::Kit::Adapters::CommandResult.new(stdout: "container-id\n", stderr: "", exit_status: 0, duration_ms: 1)
      else
        original.call(command, **arguments)
      end
    end

    change = operation.plan
    expect { operation.apply(change) }.to raise_error(Kitsune::Kit::Errors::RemoteCommandError)
    cleanup = transport.calls.find do |name, arguments|
      name == :execute && arguments[:command] == "rm" && arguments[:arguments].include?("-f")
    end
    expect(cleanup).not_to be_nil

    expect(operation.apply(change)).to be(true)
  end

  it "refuses to overwrite service files that are not present in local state" do
    compose_path = "/home/deploy/.local/share/kitsune/services/postgres/compose.yml"
    transport.stub("test", arguments: ["-e", compose_path])

    expect { operation.plan }
      .to raise_error(Kitsune::Kit::Errors::UnsafeOperationError, /unmanaged postgres service files/)
    expect(transport.uploads).to be_empty
  end

  it "backs up a managed update and restores its previous files and state on rollback" do
    first_change = operation.plan
    first_fingerprint = first_change.details.fetch(:fingerprint)
    operation.apply(first_change)

    marker = "/var/lib/kitsune/state/service-postgres.sha256"
    compose_path = "/home/deploy/.local/share/kitsune/services/postgres/compose.yml"
    env_path = "/home/deploy/.local/share/kitsune/services/postgres/.env"
    transport.stub("sudo", arguments: ["cat", marker], stdout: "#{first_fingerprint}\n")
    transport.stub("test", arguments: ["-e", compose_path])
    transport.stub("test", arguments: ["-e", env_path])
    updated = described_class.new(
      config: config,
      type: :postgres,
      transport_factory: factory,
      state_store: store,
      secret_store: Kitsune::Kit::SecretStores::Environment.new(env: { "POSTGRES_PASSWORD" => "new-secret" })
    )

    update_change = updated.plan
    expect(update_change.action).to eq("update")
    updated.apply(update_change)
    current = store.read("test").dig("resources", "service.postgres")
    expect(current["backup_directory"]).to include("service-postgres-")
    expect(current["backed_up_files"]).to contain_exactly(compose_path, env_path)

    expect(updated.rollback).to be(true)
    restored = store.read("test").dig("resources", "service.postgres")
    expect(restored["fingerprint"]).to eq(first_fingerprint)
    restore_copies = transport.calls.select do |name, arguments|
      name == :execute && arguments[:command] == "cp" && arguments[:arguments].any? { |part| part.include?("backups") }
    end
    expect(restore_copies.length).to be >= 2
  end

  it "restarts the previous service after an update fails" do
    first_change = operation.plan
    first_fingerprint = first_change.details.fetch(:fingerprint)
    operation.apply(first_change)
    marker = "/var/lib/kitsune/state/service-postgres.sha256"
    compose_path = "/home/deploy/.local/share/kitsune/services/postgres/compose.yml"
    env_path = "/home/deploy/.local/share/kitsune/services/postgres/.env"
    transport.stub("sudo", arguments: ["cat", marker], stdout: "#{first_fingerprint}\n")
    transport.stub("test", arguments: ["-e", compose_path])
    transport.stub("test", arguments: ["-e", env_path])
    update = described_class.new(
      config: config,
      type: :postgres,
      transport_factory: factory,
      state_store: store,
      secret_store: Kitsune::Kit::SecretStores::Environment.new(env: { "POSTGRES_PASSWORD" => "changed" })
    )
    allow(transport).to receive(:upload).and_wrap_original do |original, **arguments|
      raise Kitsune::Kit::Errors::ConnectionError, "upload failed" if arguments[:remote_path].end_with?(".env")

      original.call(**arguments)
    end

    expect { update.apply(update.plan) }.to raise_error(Kitsune::Kit::Errors::ConnectionError)
    restored_up = transport.calls.reverse.find do |name, arguments|
      name == :execute && arguments[:command] == "docker" && arguments[:arguments].include?("up")
    end
    expect(restored_up).not_to be_nil
    expect(store.read("test").dig("resources", "service.postgres", "fingerprint")).to eq(first_fingerprint)
  end

  it "surfaces the original and recovery failures when a managed update cannot be restored" do
    first_change = operation.plan
    first_fingerprint = first_change.details.fetch(:fingerprint)
    operation.apply(first_change)
    marker = "/var/lib/kitsune/state/service-postgres.sha256"
    compose_path = "/home/deploy/.local/share/kitsune/services/postgres/compose.yml"
    env_path = "/home/deploy/.local/share/kitsune/services/postgres/.env"
    transport.stub("sudo", arguments: ["cat", marker], stdout: "#{first_fingerprint}\n")
    transport.stub("test", arguments: ["-e", compose_path])
    transport.stub("test", arguments: ["-e", env_path])
    update = described_class.new(
      config: config, type: :postgres, transport_factory: factory, state_store: store,
      secret_store: Kitsune::Kit::SecretStores::Environment.new(env: { "POSTGRES_PASSWORD" => "changed" })
    )
    allow(transport).to receive(:upload).and_wrap_original do |original, **arguments|
      raise Kitsune::Kit::Errors::ConnectionError, "upload failed" if arguments[:remote_path].end_with?(".env")

      original.call(**arguments)
    end
    copy_count = 0
    allow(transport).to receive(:execute).and_wrap_original do |original, command, **arguments|
      copy_count += 1 if command == "cp"
      if command == "cp" && copy_count >= 3
        Kitsune::Kit::Adapters::CommandResult.new(stdout: "", stderr: "restore denied", exit_status: 2,
                                                  duration_ms: 1)
      else
        original.call(command, **arguments)
      end
    end

    expect { update.apply(update.plan) }.to raise_error(Kitsune::Kit::Errors::VerificationError) { |error|
      expect(error.message).to include("apply failed and automatic recovery also failed")
      expect(error.context).to include(original_error: "connection_error", recovery_error: "remote_command_error")
    }
  end

  it "removes only published firewall rules created by Kitsune Kit" do
    published_config = build_config(
      postgres: { enabled: true, publish: true, bind: "0.0.0.0", allowed_cidrs: ["203.0.113.8/32"] }
    )
    published = described_class.new(
      config: published_config,
      type: :postgres,
      transport_factory: factory,
      state_store: store,
      secret_store: secrets
    )
    stub_missing_iptables_rules(published_config)
    published.apply(published.plan)

    owned = store.read("test").dig("resources", "service.postgres", "firewall_rules_added")
    expect(owned).to eq(["203.0.113.8/32"])
    published.remove
    delete_call = transport.calls.find do |name, arguments|
      name == :execute && arguments[:arguments]&.include?("-D") &&
        arguments[:arguments].include?("kitsune:postgres:allow")
    end
    expect(delete_call.last[:arguments]).to include("203.0.113.8/32")
  end

  it "does not claim or remove a matching pre-existing firewall rule" do
    published_config = build_config(
      postgres: { enabled: true, publish: true, bind: "0.0.0.0", allowed_cidrs: ["203.0.113.8/32"] }
    )
    common = docker_firewall_common(published_config)
    allow_rule = ["iptables", "-C", *common, "-s", "203.0.113.8/32", "-m", "comment", "--comment",
                  "kitsune:postgres:allow", "-j", "ACCEPT"]
    drop_rule = ["iptables", "-C", *common, "-m", "comment", "--comment", "kitsune:postgres:drop", "-j", "DROP"]
    transport.stub("sudo", arguments: allow_rule)
    transport.stub("sudo", arguments: drop_rule, exit_status: 1)
    published = described_class.new(
      config: published_config,
      type: :postgres,
      transport_factory: factory,
      state_store: store,
      secret_store: secrets
    )
    published.apply(published.plan)
    expect(store.read("test").dig("resources", "service.postgres", "firewall_rules_added")).to be_empty

    published.remove
    delete_calls = transport.calls.select do |name, arguments|
      name == :execute && arguments[:arguments]&.include?("-D") &&
        arguments[:arguments].include?("kitsune:postgres:allow")
    end
    expect(delete_calls).to be_empty
  end

  it "removes newly added firewall rules when a later service marker write fails" do
    published_config = build_config(
      postgres: { enabled: true, publish: true, bind: "0.0.0.0", allowed_cidrs: ["203.0.113.8/32"] }
    )
    published = described_class.new(
      config: published_config,
      type: :postgres,
      transport_factory: factory,
      state_store: store,
      secret_store: secrets
    )
    stub_missing_iptables_rules(published_config)
    transport.stub(
      "sudo", arguments: ["tee", "/var/lib/kitsune/state/service-postgres.sha256"],
              stderr: "read-only", exit_status: 1
    )

    expect { published.apply(published.plan) }
      .to raise_error(Kitsune::Kit::Errors::RemoteCommandError, /write service marker/)

    deleted = transport.calls.select do |name, arguments|
      name == :execute && arguments[:arguments]&.include?("-D") &&
        arguments[:arguments].include?("kitsune:postgres:allow")
    end
    expect(deleted).not_to be_empty
    expect(store.read("test").dig("resources", "service.postgres")).to be_nil
  end

  private

  def docker_firewall_common(current_config)
    service = current_config.services.postgres
    ["DOCKER-USER", "-p", "tcp", "-m", "conntrack", "--ctorigdstport", service.port.to_s,
     "--ctdir", "ORIGINAL"]
  end

  def stub_missing_iptables_rules(current_config)
    common = docker_firewall_common(current_config)
    allow_rule = ["iptables", "-C", *common, "-s", "203.0.113.8/32", "-m", "comment", "--comment",
                  "kitsune:postgres:allow", "-j", "ACCEPT"]
    drop_rule = ["iptables", "-C", *common, "-m", "comment", "--comment", "kitsune:postgres:drop", "-j", "DROP"]
    transport.stub("sudo", arguments: allow_rule, exit_status: 1)
    transport.stub("sudo", arguments: drop_rule, exit_status: 1)
  end
end
