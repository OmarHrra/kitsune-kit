# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "yaml"
require "spec_helper"

RSpec.describe Kitsune::Kit::Workflows::EjectCompose do
  let(:root) { Dir.mktmpdir("kitsune-eject") }
  let(:config_path) { File.join(root, ".kitsune/config.yml") }

  before do
    Kitsune::Kit::Workflows::InitializeProject.new(root: root).call
  end

  after { FileUtils.remove_entry(root) }

  it "creates an editable Compose file, a backup and custom mode configuration" do
    config = load_config
    result = described_class.new(root: root, config: config, type: "postgres").call
    document = YAML.safe_load_file(config_path)

    expect(File.read(result.fetch(:compose_file))).to include("services:", "postgres:")
    expect(File.read(result.fetch(:backup_file))).to include("mode: generated")
    expect(document.dig("services", "postgres", "compose")).to eq(
      "mode" => "custom", "file" => ".kitsune/compose/postgres.yml", "allow_unsafe" => false
    )
  end

  it "does not overwrite ejected files without force" do
    workflow = described_class.new(root: root, config: load_config, type: "redis")
    workflow.call

    expect { workflow.call }.to raise_error(Kitsune::Kit::Errors::UnsafeOperationError)
    expect(YAML.safe_load_file(config_path).dig("services", "redis", "compose", "mode")).to eq("custom")
  end

  private

  def load_config
    document = YAML.safe_load_file(config_path)
    key = File.join(root, "test-key")
    File.write(key, "fixture private key")
    File.chmod(0o600, key)
    document["ssh"]["key_path"] = key
    File.write(config_path, YAML.dump(document))
    File.chmod(0o600, config_path)
    Kitsune::Kit::Configuration::Loader.new(root: root, env: { "DO_API_TOKEN" => "token" }).load
  end
end
