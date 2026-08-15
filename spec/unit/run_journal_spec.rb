# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "spec_helper"

RSpec.describe Kitsune::Kit::RunJournal do
  let(:root) { Dir.mktmpdir("kitsune-journal") }
  let(:store) { Kitsune::Kit::StateStore.new(root: root) }
  subject(:journal) do
    described_class.new(state_store: store, environment: "test", run_id: "run-1", clock: -> { Time.utc(2026) })
  end

  after { FileUtils.remove_entry(root) }

  it "is a no-op when persistence is deliberately unavailable" do
    transient = described_class.new(state_store: nil, environment: "test", run_id: "run")
    expect(transient.start(changes: [])).to be_nil
    expect(transient.record_step("server", "success")).to be_nil
    expect(transient.finish("success")).to be_nil
  end

  it "selects the latest resumable run and rejects missing IDs" do
    store.update("test") do |state|
      state["runs"] = {
        "success" => { "status" => "success", "changes" => [], "steps" => {} },
        "failed" => { "status" => "failure", "changes" => [], "steps" => {} }
      }
      state
    end

    expect(journal.resumable.first).to eq("failed")
    expect { journal.resumable("missing") }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /run not found/)
  end

  it "rejects absent, successful and structurally corrupt resume plans" do
    expect { journal.resumable }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /no run available/)

    store.update("test") do |state|
      state["runs"]["success"] = { "status" => "success", "changes" => [], "steps" => {} }
      state["runs"]["broken"] = { "status" => "failure", "changes" => nil, "steps" => [] }
      state
    end
    expect { journal.resumable("success") }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /cannot be resumed/)
    expect { journal.resumable("broken") }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /does not contain a resumable plan/)
  end
end
