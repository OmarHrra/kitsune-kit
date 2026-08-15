# frozen_string_literal: true

require "json"
require "open3"
require "securerandom"
require "socket"
require "tmpdir"
require "yaml"
require "spec_helper"

RSpec.describe "DigitalOcean lifecycle", :e2e do
  before do
    skip "Set KITSUNE_E2E=1 to authorize real, billable infrastructure" unless ENV["KITSUNE_E2E"] == "1"
    missing = required_environment.select { |name| ENV.fetch(name, "").empty? }
    raise "Missing E2E environment variables: #{missing.join(', ')}" if missing.any?

    verify_ssh_key_pair!
  end

  def required_environment = %w[DO_API_TOKEN KITSUNE_E2E_SSH_KEY_ID KITSUNE_E2E_KEY_PATH]

  def verify_ssh_key_pair!
    path = ENV.fetch("KITSUNE_E2E_KEY_PATH")
    public_key, error, status = Open3.capture3("ssh-keygen", "-y", "-f", path)
    raise "Unable to read KITSUNE_E2E_KEY_PATH: #{error.strip}" unless status.success?

    remote = DropletKit::Client.new(access_token: ENV.fetch("DO_API_TOKEN")).ssh_keys.find(
      id: ENV.fetch("KITSUNE_E2E_SSH_KEY_ID")
    )
    normalize = ->(key) { key.to_s.split.first(2).join(" ") }
    return if normalize.call(public_key) == normalize.call(remote.public_key)

    raise "KITSUNE_E2E_KEY_PATH does not match DigitalOcean SSH key " \
          "#{remote.id} (#{remote.name}); no Droplet was created"
  end

  def write_configuration(root, name, expires_at)
    FileUtils.mkdir_p(File.join(root, ".kitsune", "environments"), mode: 0o700)
    data = Kitsune::Kit::Configuration::DEFAULTS.merge(
      "server" => Kitsune::Kit::Configuration::DEFAULTS.fetch("server").merge(
        "name" => name,
        "region" => ENV.fetch("KITSUNE_E2E_REGION", "sfo3"),
        "size" => ENV.fetch("KITSUNE_E2E_SIZE", "s-1vcpu-1gb"),
        "ssh_key_id" => ENV.fetch("KITSUNE_E2E_SSH_KEY_ID"),
        "tags" => ["kitsune-managed", "kitsune-ci", "kitsune-expires-#{expires_at}"]
      ),
      "ssh" => Kitsune::Kit::Configuration::DEFAULTS.fetch("ssh").merge(
        "key_path" => ENV.fetch("KITSUNE_E2E_KEY_PATH")
      ),
      "services" => {
        "postgres" => Kitsune::Kit::Configuration::DEFAULTS.dig("services", "postgres").merge("enabled" => true),
        "redis" => Kitsune::Kit::Configuration::DEFAULTS.dig("services", "redis").merge("enabled" => true)
      }
    )
    File.write(File.join(root, ".kitsune", "config.yml"), YAML.dump(data), mode: "w", perm: 0o600)
  end

  def run_cli(root, *arguments)
    command = [Gem.ruby, "-I#{File.expand_path('../../lib', __dir__)}", File.expand_path("../../bin/kit", __dir__),
               *arguments, "--root", root, "--env", "e2e", "--no-input", "--no-log", "--format", "json"]
    stdout, stderr, status = Open3.capture3(ENV.to_h, *command)
    raise "CLI failed (#{status.exitstatus}): #{stderr}\n#{stdout}" unless status.success?

    JSON.parse(stdout)
  end

  def externally_closed?(host, port)
    Socket.tcp(host, port, connect_timeout: 3).close
    false
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ETIMEDOUT, IO::TimeoutError
    true
  end

  it "creates, configures, verifies, reapplies, rolls back and destroys without leaking data ports" do
    Dir.mktmpdir("kitsune-e2e") do |root|
      name = "kitsune-ci-#{Time.now.utc.strftime('%Y%m%d%H%M')}-#{SecureRandom.hex(3)}"
      write_configuration(root, name, Time.now.to_i + 7200)
      ENV["POSTGRES_PASSWORD"] = SecureRandom.base64(36)
      ENV["REDIS_PASSWORD"] = SecureRandom.base64(36)
      app = Kitsune::Kit::Application.build(
        root: root, environment: "e2e", env: ENV,
        host_key_confirmation: ->(**) { true }, maximum_timeout: 300
      )
      app.provider.validate_credentials!

      begin
        first_plan = Kitsune::Kit::Workflows::BuildPlan.new(
          config: app.config, operations: app.operations, event_bus: app.event_bus
        ).call.value
        expect(first_plan).to be_changed
        Kitsune::Kit::Workflows::ApplyPlan.new(
          config: app.config, operations: app.operations, state_store: app.state_store,
          event_bus: app.event_bus
        ).call(plan: first_plan)

        doctor = run_cli(root, "doctor")
        expect(doctor.fetch("status")).to eq("success")
        expect(run_cli(root, "plan").fetch("status")).to eq("success")

        second_plan = Kitsune::Kit::Workflows::BuildPlan.new(
          config: app.config, operations: app.operations, event_bus: app.event_bus
        ).call.value
        expect(second_plan.changed_count).to eq(0)

        server = app.provider.find_server(name: app.config.server.name, tags: app.config.server.tags)
        expect(server).not_to be_nil
        expect(externally_closed?(server.public_ip, 5432)).to be(true)
        expect(externally_closed?(server.public_ip, 6379)).to be(true)

        rollback = Kitsune::Kit::Workflows::Rollback.new(
          config: app.config, operations: app.operations.drop(1), state_store: app.state_store,
          event_bus: app.event_bus
        ).call
        expect(rollback).to be_success
        remaining = app.state_store.read(app.config.environment).fetch("resources").keys
        expect(remaining).to eq(["server"])
        expect(app.transport_factory.root.reachable?).to be(true)
      ensure
        state = app.state_store.read(app.config.environment)
        if state.dig("resources", "server", "id")
          Kitsune::Kit::Workflows::DestroyServer.new(
            config: app.config, provider: app.provider, state_store: app.state_store
          ).call(confirmation: app.config.server.name)
        else
          orphan = app.provider.find_server(name: app.config.server.name, tags: app.config.server.tags)
          app.provider.delete_server(id: orphan.id) if orphan
        end
      end
    end
  end
end
