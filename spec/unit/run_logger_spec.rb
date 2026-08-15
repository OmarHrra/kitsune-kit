# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "spec_helper"

RSpec.describe Kitsune::Kit::RunLogger do
  let(:root) { Dir.mktmpdir("kitsune-logger") }

  after { FileUtils.remove_entry(root) }

  it "writes structured events with restricted permissions and redacted secrets" do
    logger = described_class.new(
      root: root,
      run_id: "run-1",
      secret_filter: Kitsune::Kit::SecretFilter.new(["top-secret"])
    )
    event = Kitsune::Kit::Events::Event.build(
      "warning_emitted",
      run_id: "run-1",
      message: "token=top-secret"
    )

    logger.handle(event)

    expect(File.read(logger.path)).to include("[REDACTED]")
    expect(File.read(logger.path)).not_to include("top-secret")
    expect(File.stat(logger.path).mode & 0o777).to eq(0o600)
  end

  it "keeps only the configured number of most recent local logs" do
    (described_class::MAX_FILES + 3).times do |index|
      described_class.new(root: root, run_id: "run-#{index}")
      sleep 0.002
    end

    logs = Dir[File.join(root, ".kitsune/logs/*.jsonl")]
    expect(logs.length).to eq(described_class::MAX_FILES)
    expect(logs.map { |path| File.basename(path) }).to all(satisfy { |name| name !~ /run-[012]\.jsonl\z/ })
  end
end
