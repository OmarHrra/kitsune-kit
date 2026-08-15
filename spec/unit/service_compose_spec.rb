# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "spec_helper"

RSpec.describe Kitsune::Kit::ServiceCompose do
  let(:root) { Dir.mktmpdir("kitsune-compose") }

  after { FileUtils.remove_entry(root) }

  it "keeps generated mode deterministic" do
    config = build_config(postgres: { enabled: true })
    first = described_class.new(config: config, type: "postgres", service: config.services.postgres)
    second = described_class.new(config: config, type: "postgres", service: config.services.postgres)

    expect(first.filenames).to eq(["compose.yml"])
    expect(first.fingerprint).to eq(second.fingerprint)
    expect(first.metadata).to include(mode: "generated", security_findings: [])
  end

  it "combines a generated base with a project overlay" do
    path = write_compose("services:\n  postgres:\n    environment:\n      LOG_STATEMENTS: all\n")
    config = compose_config("overlay", path)
    compose = described_class.new(config: config, type: "postgres", service: config.services.postgres)

    expect(compose.filenames).to eq(%w[compose.yml compose.override.yml])
    expect(compose.documents.last).to have_attributes(source: path)
  end

  it "accepts a complete custom service using environment references" do
    path = write_compose(<<~YAML)
      services:
        postgres:
          image: postgres:17
          environment:
            POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    YAML
    config = compose_config("custom", path)

    compose = described_class.new(config: config, type: "postgres", service: config.services.postgres)
    expect(compose.content).to include("${POSTGRES_PASSWORD}")
  end

  it "rejects inline secrets and unsafe container privileges by default" do
    secret_path = write_compose("services:\n  postgres:\n    password: visible-secret\n")
    expect { build_compose("custom", secret_path) }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /inline secret/)

    unsafe_path = write_compose("services:\n  postgres:\n    privileged: true\n")
    expect { build_compose("custom", unsafe_path) }
      .to raise_error(Kitsune::Kit::Errors::UnsafeOperationError) { |error|
        expect(error.context.fetch(:findings).first.fetch(:path)).to eq("services.postgres.privileged")
      }
  end

  it "rejects incomplete, oversized and non-mapping custom documents" do
    missing = write_compose("services:\n  redis:\n    image: redis:7.2\n")
    expect { build_compose("custom", missing) }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /must define services.postgres/)

    list = write_compose("- services\n- postgres\n")
    expect { build_compose("custom", list) }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /YAML mapping/)

    large = write_compose("x" * (Kitsune::Kit::ServiceCompose::MAX_FILE_SIZE + 1))
    expect { build_compose("custom", large) }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /exceeds 256 KiB/)
  end

  it "detects secrets in environment-list syntax" do
    path = write_compose(<<~YAML)
      services:
        postgres:
          environment:
            - POSTGRES_PASSWORD=visible-secret
    YAML

    expect { build_compose("custom", path) }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /inline secret/)
  end

  it "permits reviewed unsafe options only through the explicit escape hatch" do
    path = write_compose(<<~YAML)
      services:
        postgres:
          network_mode: host
          cap_add: [SYS_ADMIN]
          ports: ["15432:5432"]
          devices: ["/dev/null:/dev/null"]
          build: .
          env_file: .env.unmanaged
          volumes:
            - /etc:/host-etc
            - type: bind
              source: /tmp
              target: /host-tmp
    YAML
    config = compose_config("custom", path, allow_unsafe: true)
    compose = described_class.new(config: config, type: "postgres", service: config.services.postgres)

    expect(compose.security_findings.map { |finding| finding.fetch(:path) }).to include(
      "services.postgres.network_mode", "services.postgres.cap_add", "services.postgres.ports",
      "services.postgres.devices", "services.postgres.build", "services.postgres.env_file",
      "services.postgres.volumes"
    )
    expect(compose.metadata.fetch(:allow_unsafe)).to be(true)
  end

  private

  def write_compose(content)
    path = File.join(root, "compose-#{Dir.children(root).length}.yml")
    File.write(path, content)
    path
  end

  def compose_config(mode, path, allow_unsafe: false)
    build_config(
      postgres: {
        enabled: true,
        compose: { mode: mode, file: path, allow_unsafe: allow_unsafe }
      }
    )
  end

  def build_compose(mode, path)
    config = compose_config(mode, path)
    described_class.new(config: config, type: "postgres", service: config.services.postgres)
  end
end
