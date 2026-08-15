# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "yaml"
require "spec_helper"

RSpec.describe Kitsune::Kit::Configuration::Loader do
  let(:root) { Dir.mktmpdir("kitsune-config") }
  let(:env) { { "DO_API_TOKEN" => "token" } }

  before do
    File.write(File.join(root, "test-key"), "fixture private key")
    File.chmod(0o600, File.join(root, "test-key"))
  end

  after { FileUtils.remove_entry(root) }

  it "combines defaults, project, environment, ENV and CLI in documented precedence" do
    write_config(
      "server" => { "name" => "project", "ssh_key_id" => "10", "region" => "nyc3" },
      "ssh" => { "port" => 2200 }
    )
    write_environment("server" => { "name" => "environment" }, "ssh" => { "port" => 2201 })
    env["KITSUNE_SERVER_NAME"] = "from-env"

    config = described_class.new(root: root, env: env).load(
      environment: "test",
      overrides: { server: { name: "from-cli" } }
    )

    expect(config.server.name).to eq("from-cli")
    expect(config.server.region).to eq("nyc3")
    expect(config.ssh.port).to eq(2201)
    expect(config.server.image).to eq("ubuntu-24-04-x64")
  end

  it "fails with an actionable error when config.yml is absent" do
    expect { described_class.new(root: root, env: env).load }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError) { |error| expect(error.hint).to include("kit init") }
  end

  it "rejects unknown top-level keys" do
    write_config("server" => valid_server, "surprise" => true)

    expect { described_class.new(root: root, env: env).load }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /unknown keys: surprise/)
  end

  it "rejects unsupported schema versions with upgrade or migration guidance" do
    write_config("version" => 99, "server" => valid_server)

    expect { described_class.new(root: root, env: env).load }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError) { |error|
        expect(error.message).to include("unsupported configuration schema version 99", "expected 1")
        expect(error.hint).to match(/compatible|migrate/i)
      }
  end

  it "rejects unknown nested keys and malformed sections as configuration errors" do
    write_config("server" => valid_server.merge("typo_region" => "moon"))
    expect { described_class.new(root: root, env: env).load }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /server contains unknown keys: typo_region/)

    write_config("server" => valid_server, "services" => ["postgres"])
    expect { described_class.new(root: root, env: env).load }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /services must be a mapping/)
  end

  it "requires allowed CIDRs before publishing a data service" do
    write_config(
      "server" => valid_server,
      "services" => { "postgres" => { "enabled" => true, "publish" => true } }
    )
    env["POSTGRES_PASSWORD"] = "strong-test-value"

    expect { described_class.new(root: root, env: env).load }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /allowed_cidrs/)
  end

  it "supports validated external services without planning local Docker resources" do
    write_config(
      "server" => valid_server,
      "services" => {
        "postgres" => { "enabled" => true, "mode" => "external", "host" => "db.internal.example" }
      }
    )
    env["POSTGRES_PASSWORD"] = "strong-external-secret"

    service = described_class.new(root: root, env: env).load.services.postgres
    expect(service).to have_attributes(enabled: true, mode: "external", host: "db.internal.example", port: 5432)

    write_config(
      "server" => valid_server,
      "services" => {
        "postgres" => { "enabled" => true, "mode" => "external", "host" => "bad host", "publish" => true }
      }
    )
    expect { described_class.new(root: root, env: env).load }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError) { |error|
        expect(error.message).to include("valid hostname or IP", "publish must be false")
      }
  end

  it "requires service secrets only when the service is enabled" do
    write_config("server" => valid_server, "services" => { "redis" => { "enabled" => true } })

    expect { described_class.new(root: root, env: env).load }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /REDIS_PASSWORD/)
  end

  it "rejects a missing or overly permissive private key before constructing external adapters" do
    write_config("server" => valid_server, "ssh" => { "key_path" => File.join(root, "missing") })
    expect { described_class.new(root: root, env: env).load }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /does not exist/)

    key = File.join(root, "open-key")
    File.write(key, "fixture")
    File.chmod(0o644, key)
    write_config("server" => valid_server, "ssh" => { "key_path" => key })
    expect { described_class.new(root: root, env: env).load }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /permissions must be 0600 or stricter/)
  end

  it "rejects known default service passwords" do
    write_config("server" => valid_server, "services" => { "postgres" => { "enabled" => true } })
    env["POSTGRES_PASSWORD"] = "postgres"

    expect { described_class.new(root: root, env: env).load }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /known insecure default/)
  end

  it "rejects service passwords that are too short for unattended infrastructure" do
    write_config("server" => valid_server, "services" => { "redis" => { "enabled" => true } })
    env["REDIS_PASSWORD"] = "short"

    expect { described_class.new(root: root, env: env).load }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /at least 12 bytes/)
  end

  it "rejects shell metacharacters in resource names and ports" do
    write_config("server" => valid_server.merge("name" => "bad; touch-pwned"))

    expect { described_class.new(root: root, env: env).load }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /invalid format/)
  end

  it "rejects service image and bind values that could alter generated Compose YAML" do
    write_config(
      "server" => valid_server,
      "services" => { "postgres" => { "image" => "postgres:17\nprivileged: true", "bind" => "0.0.0.0;bad" } }
    )

    expect { described_class.new(root: root, env: env).load }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError) do |error|
        expect(error.message).to include("image has an invalid format", "bind must be an IP address")
      end
  end

  it "rejects path traversal in environment names before reading files" do
    write_config("server" => valid_server)

    expect { described_class.new(root: root, env: env).load(environment: "../../outside") }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /environment name/)
  end

  it "rejects uppercase environment names that are unsafe for Compose project identity" do
    write_config("server" => valid_server)

    expect { described_class.new(root: root, env: env).load(environment: "Production") }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /environment name/)
  end

  it "uses the persisted environment after explicit CLI and environment-variable selection" do
    write_config("server" => valid_server)
    write_environment("server" => { "name" => "selected-test" })
    File.write(File.join(root, ".kitsune/environment"), "test\n")

    config = described_class.new(root: root, env: env).load

    expect(config.environment).to eq("test")
    expect(config.server.name).to eq("selected-test")
  end

  it "loads an explicit project configuration path" do
    custom = File.join(root, "custom-kitsune.yml")
    File.write(custom, YAML.dump(
                         "version" => 1,
                         "server" => valid_server.merge("name" => "custom"),
                         "ssh" => { "key_path" => File.join(root, "test-key") }
                       ))

    config = described_class.new(root: root, env: env, config_path: custom).load(environment: "test")

    expect(config.server.name).to eq("custom")
  end

  it "preserves explicit false system feature flags" do
    write_config(
      "server" => valid_server,
      "system" => { "unattended_upgrades" => false, "metrics" => false }
    )

    config = described_class.new(root: root, env: env).load

    expect(config.system.unattended_upgrades).to be(false)
    expect(config.system.metrics).to be(false)
  end

  it "requires a verified installer digest when metrics is enabled" do
    write_config("server" => valid_server, "system" => { "metrics" => true })

    expect { described_class.new(root: root, env: env).load }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /metrics_installer_sha256/)
  end

  it "reports all unsafe and out-of-range schema values together" do
    write_config(
      "version" => 1,
      "provider" => { "name" => "unknown", "token_env" => "bad-token" },
      "server" => { "name" => "", "region" => "", "size" => "", "image" => "debian",
                    "ssh_key_id" => "" },
      "ssh" => { "user" => "Bad User", "port" => 0, "allowed_cidrs" => ["not-a-cidr"] },
      "services" => {
        "postgres" => { "enabled" => true, "publish" => true, "allowed_cidrs" => [], "port" => 0,
                        "image" => "bad image", "password_env" => "bad-secret", "bind" => "::1" },
        "redis" => { "bind" => "not-an-ip", "allowed_cidrs" => ["bad-cidr"] }
      },
      "system" => { "swap_size_gb" => -1, "swap_swappiness" => 101, "metrics" => true,
                    "metrics_installer_sha256" => "BAD" },
      "dns" => { "ttl" => 1, "domains" => ["bad_domain.example", "a" * 254] }
    )

    expect { described_class.new(root: root, env: env).load }.to raise_error(
      Kitsune::Kit::Errors::ConfigurationError
    ) do |error|
      expect(error.message).to include(
        "provider.name", "provider.token_env", "server.name is required",
        "server.region is required", "server.size is required", "server.image is unsupported",
        "server.ssh_key_id is required", "ssh.user", "ssh.port", "invalid CIDR",
        "bind must be an IPv4 address", "bind must be an IP address", "swap_size_gb",
        "swap_swappiness", "dns.ttl", "invalid DNS name"
      )
    end
  end

  it "normalizes string service booleans and rejects untyped scalar values" do
    write_config(
      "server" => valid_server,
      "services" => { "postgres" => { "enabled" => "true", "publish" => "false" } }
    )
    env["POSTGRES_PASSWORD"] = "strong-test-secret"
    config = described_class.new(root: root, env: env).load
    expect(config.services.postgres.enabled).to be(true)
    expect(config.services.postgres.publish).to be(false)

    write_config("server" => valid_server, "services" => { "postgres" => { "enabled" => "perhaps" } })
    expect { described_class.new(root: root, env: env).load }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /expected a boolean/)
  end

  it "maps malformed YAML shapes and scalar types to actionable configuration errors" do
    path = File.join(root, ".kitsune/config.yml")
    FileUtils.mkdir_p(File.dirname(path))

    File.write(path, "- not\n- a mapping\n")
    expect { described_class.new(root: root, env: env).load }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /must contain a YAML mapping/)

    File.write(path, "server: [unterminated\n")
    expect { described_class.new(root: root, env: env).load }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /invalid YAML/)

    write_config("server" => valid_server, "ssh" => { "port" => "not-a-number" })
    expect { described_class.new(root: root, env: env).load }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /ssh.port must be an integer/)

    write_config("server" => valid_server, "system" => { "metrics" => "false" })
    expect { described_class.new(root: root, env: env).load }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /expected a boolean/)

    write_config("server" => valid_server, "dns" => { "ttl" => "never" })
    expect { described_class.new(root: root, env: env).load }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /dns.ttl must be an integer/)
  end

  private

  def valid_server
    { "name" => "myapp-test", "ssh_key_id" => "10" }
  end

  def write_config(extra)
    path = File.join(root, ".kitsune/config.yml")
    FileUtils.mkdir_p(File.dirname(path))
    payload = { "version" => 1 }.merge(extra)
    payload["ssh"] = { "key_path" => File.join(root, "test-key") }.merge(payload.fetch("ssh", {}))
    File.write(path, YAML.dump(payload))
  end

  def write_environment(extra)
    path = File.join(root, ".kitsune/environments/test.yml")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, YAML.dump({ "version" => 1 }.merge(extra)))
  end
end
