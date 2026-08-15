# frozen_string_literal: true

require "spec_helper"
require "kitsune/kit/cli"
require "open3"
require "tmpdir"

RSpec.describe "bin/kit CLI", type: :integration do
  let(:bin_path) { File.expand_path("../../../bin/kit", __dir__) }
  let(:expected_version) { "Kitsune Kit #{Kitsune::Kit::VERSION}" }

  it "prints version with -v" do
    output = `#{bin_path} -v`.strip
    expect(output).to eq(expected_version)
  end

  it "prints version with --version" do
    output = `#{bin_path} --version`.strip
    expect(output).to eq(expected_version)
  end

  it "prints version with version subcommand" do
    output = `#{bin_path} version`.strip
    expect(output).to eq(expected_version)
  end

  it "returns code 2 and a concise message for invalid CLI usage" do
    _stdout, stderr, status = Open3.capture3(bin_path, "does-not-exist")

    expect(status.exitstatus).to eq(2)
    expect(stderr).to include('Could not find command "does-not-exist"')

    _stdout, stderr, status = Open3.capture3(bin_path, "plan", "--format", "xml")
    expect(status.exitstatus).to eq(2)
    expect(stderr).to include("Expected '--format' to be one of human, json; got xml")
  end

  it "supports a complete non-interactive init and environment-selection flow" do
    Dir.mktmpdir("kitsune-cli") do |root|
      stdout, stderr, status = Open3.capture3(
        bin_path, "init", "--root", root, "--format", "json", "--no-log"
      )
      payload = JSON.parse(stdout)
      expect(status).to be_success
      expect(stderr).to be_empty
      expect(payload).to include(
        "schema_version" => 1, "command" => "init", "environment" => "development", "status" => "success"
      )
      expect(payload["result"]).to include(File.join(root, ".kitsune/config.yml"))

      stdout, = Open3.capture3(bin_path, "env", "list", "--root", root, "--format", "json", "--no-log")
      expect(JSON.parse(stdout).fetch("result")).to eq(["development"])

      stdout, = Open3.capture3(bin_path, "env", "current", "--root", root, "--no-log")
      expect(stdout.strip).to eq("development")
    end
  end

  it "shows, validates, diffs and ejects Compose without a TUI" do
    Dir.mktmpdir("kitsune-cli-compose") do |root|
      Open3.capture3(bin_path, "init", "--root", root, "--no-log")
      key = File.join(root, "test-key")
      File.write(key, "fixture private key")
      File.chmod(0o600, key)
      config_path = File.join(root, ".kitsune/config.yml")
      config = YAML.safe_load_file(config_path)
      config["ssh"]["key_path"] = key
      config["services"]["postgres"]["enabled"] = true
      File.write(config_path, YAML.dump(config))

      local_environment = { "DO_API_TOKEN" => nil, "POSTGRES_PASSWORD" => nil }

      stdout, stderr, status = Open3.capture3(
        local_environment, bin_path, "service", "postgres", "compose", "show", "--root", root, "--no-log"
      )
      expect(status).to be_success
      expect(stderr).to be_empty
      expect(stdout).to include("compose.yml (generated)", "POSTGRES_PASSWORD")

      stdout, stderr, status = Open3.capture3(
        local_environment, bin_path, "service", "postgres", "compose", "diff", "--root", root,
        "--format", "json", "--no-log"
      )
      expect(status).to be_success
      expect(stderr).to be_empty
      expect(JSON.parse(stdout).dig("result", "changed")).to be(true)

      _stdout, stderr, status = Open3.capture3(
        local_environment, bin_path, "service", "postgres", "compose", "eject", "--root", root, "--no-log"
      )
      expect(status).to be_success
      expect(stderr).to be_empty
      expect(File).to exist(File.join(root, ".kitsune/compose/postgres.yml"))

      stdout, stderr, status = Open3.capture3(
        local_environment, bin_path, "service", "postgres", "compose", "validate", "--root", root, "--no-log"
      )
      expect(status).to be_success
      expect(stderr).to be_empty
      expect(stdout).to include("valid (custom)")
    end
  end

  it "falls back to help without a TTY and refuses explicit TUI mode with a stable code" do
    stdout, stderr, status = Open3.capture3(bin_path)
    expect(status).to be_success
    expect(stderr).to be_empty
    expect(stdout).to include("Kitsune Kit commands:", "kit ui")

    _stdout, stderr, status = Open3.capture3(bin_path, "ui", "--format", "json")
    expect(status.exitstatus).to eq(3)
    error = JSON.parse(stderr)
    expect(error.dig("error", "code")).to eq("configuration_error")
  end

  it "provides successful, ANSI-free help for every public command" do
    Kitsune::Kit::CLI.tasks.each_key do |command|
      stdout, stderr, status = Open3.capture3({ "NO_COLOR" => "1" }, bin_path, "help", command)
      expect(status).to be_success, "help failed for #{command}: #{stderr}"
      expect(stdout).to include("Usage:")
      expect(stdout).not_to include("\e[")

      alternate, alternate_error, alternate_status = Open3.capture3(
        { "NO_COLOR" => "1" }, bin_path, command, "help"
      )
      expect(alternate_status).to be_success, "alternate help failed for #{command}: #{alternate_error}"
      expect(alternate).to eq(stdout)
    end
  end

  it "returns typed JSON errors for invalid domain actions" do
    Dir.mktmpdir("kitsune-cli") do |root|
      Open3.capture3(bin_path, "init", "--root", root, "--no-log")

      _stdout, stderr, status = Open3.capture3(
        bin_path, "env", "unknown", "--root", root, "--format", "json", "--no-log"
      )
      expect(status.exitstatus).to eq(3)
      expect(JSON.parse(stderr).dig("error", "code")).to eq("configuration_error")

      _stdout, stderr, status = Open3.capture3(
        bin_path, "init", "--root", root, "--format", "json", "--no-log"
      )
      expect(status.exitstatus).to eq(9)
      expect(JSON.parse(stderr).dig("error", "code")).to eq("unsafe_operation")
    end
  end

  it "reports human log paths without contaminating JSON output" do
    Dir.mktmpdir("kitsune-cli-log") do |root|
      Open3.capture3(bin_path, "init", "--root", root, "--no-log")

      stdout, _stderr, status = Open3.capture3(bin_path, "plan", "--root", root, "--no-input")
      expect(status).not_to be_success
      expect(stdout).to match(%r{Log: .*/\.kitsune/logs/.*\.jsonl})
      expect(Dir[File.join(root, ".kitsune/logs/*.jsonl")]).not_to be_empty

      stdout, stderr, status = Open3.capture3(
        bin_path, "plan", "--root", root, "--no-input", "--format", "json"
      )
      expect(status).not_to be_success
      expect(stdout).to be_empty
      expect(JSON.parse(stderr).fetch("status")).to eq("failure")
    end
  end
end
