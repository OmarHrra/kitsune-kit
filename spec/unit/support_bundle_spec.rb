# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require "spec_helper"

RSpec.describe Kitsune::Kit::Workflows::SupportBundle do
  let(:root) { Dir.mktmpdir("kitsune-support") }
  let(:config) { build_config }
  let(:store) { Kitsune::Kit::StateStore.new(root: root) }
  let(:check) do
    Kitsune::Kit::Workflows::Check.new(
      name: "Provider", status: "fail", message: "token top-secret failed", hint: "Check top-secret"
    )
  end
  let(:doctor) { instance_double(Kitsune::Kit::Workflows::Doctor, call: Kitsune::Kit::Result.success([check])) }
  let(:clock) { -> { Time.utc(2026, 8, 13, 12, 0, 0) } }

  after { FileUtils.remove_entry(root) }

  it "creates a restricted, inspectable and fully redacted diagnostic file" do
    log_directory = File.join(root, ".kitsune/logs")
    FileUtils.mkdir_p(log_directory)
    File.write(File.join(log_directory, "run.jsonl"), JSON.generate(message: "top-secret") << "\ninvalid\n")
    store.update("test") do |state|
      state["resources"]["server"] = { "id" => "server-1", "note" => "top-secret" }
      state
    end
    workflow = described_class.new(
      root: root,
      config: config,
      state_store: store,
      doctor: doctor,
      secret_filter: Kitsune::Kit::SecretFilter.new(["top-secret"]),
      clock: clock
    )

    path = workflow.call
    payload = JSON.parse(File.read(path))

    expect(File.stat(path).mode & 0o777).to eq(0o600)
    expect(payload).to include("schema_version" => 1, "kitsune_version" => Kitsune::Kit::VERSION)
    expect(payload.dig("configuration", "provider", "token_env")).to eq("[REDACTED]")
    expect(payload["logs"].first["events"].last["type"]).to eq("invalid_log_line")
    expect(File.read(path)).not_to include("top-secret")
    expect(File.read(path)).to include("[REDACTED]")
  end
end
