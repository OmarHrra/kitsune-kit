# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "spec_helper"

RSpec.describe Kitsune::Kit::StateStore do
  let(:root) { Dir.mktmpdir("kitsune-state") }
  subject(:store) { described_class.new(root: root) }

  after { FileUtils.remove_entry(root) }

  it "returns a versioned empty state" do
    expect(store.read("test")).to include(
      "version" => 1,
      "environment" => "test",
      "resources" => {},
      "operations" => []
    )
  end

  it "writes state atomically with restrictive permissions" do
    store.update("test") do |state|
      state["resources"]["server"] = { "id" => "srv-1" }
      state
    end

    path = File.join(root, ".kitsune/state/test.json")
    expect(store.read("test").dig("resources", "server", "id")).to eq("srv-1")
    expect(File.stat(path).mode & 0o777).to eq(0o600)
    expect(Dir.glob("#{path}*.tmp")).to be_empty
  end

  it "keeps a recoverable backup of the previous state" do
    store.update("test") { |state| state.tap { |value| value["resources"]["counter"] = 1 } }
    store.update("test") { |state| state.tap { |value| value["resources"]["counter"] = 2 } }

    backup = JSON.parse(File.read(File.join(root, ".kitsune/state/test.json.backup")))
    expect(backup.dig("resources", "counter")).to eq(1)
  end

  it "rejects unsafe environment names" do
    expect { store.read("../../outside") }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /invalid format/)
  end

  it "rejects corrupted state" do
    path = File.join(root, ".kitsune/state/test.json")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "not-json")

    expect { store.read("test") }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /invalid JSON/)
  end

  it "rejects every incompatible state shape instead of repairing it silently" do
    valid = store.read("test")
    invalid = [
      [[], /must be an object/],
      [valid.merge("version" => 99), /unsupported state schema version/],
      [valid.merge("environment" => "other"), /environment mismatch/],
      [valid.merge("resources" => []), /resources must be an object/],
      [valid.merge("operations" => {}), /operations must be an array/],
      [valid.merge("runs" => []), /runs must be an object/]
    ]
    path = File.join(root, ".kitsune/state/test.json")
    FileUtils.mkdir_p(File.dirname(path))

    invalid.each do |state, message|
      File.write(path, JSON.generate(state))
      expect { store.read("test") }.to raise_error(Kitsune::Kit::Errors::ConfigurationError, message)
    end
  end

  it "rejects future state schemas with compatibility guidance" do
    path = File.join(root, ".kitsune/state/test.json")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.generate(store.read("test").merge("version" => 99)))

    expect { store.read("test") }.to raise_error(Kitsune::Kit::Errors::ConfigurationError) { |error|
      expect(error.message).to include("unsupported state schema version 99", "expected 1")
      expect(error.hint).to match(/compatible|backup/i)
    }
  end

  it "maps invalid JSON encountered during a locked update" do
    path = File.join(root, ".kitsune/state/test.json")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "{")

    expect { store.update("test") { |state| state } }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /invalid JSON/)
  end

  it "serializes concurrent updates and supports idempotent deletion" do
    store.update("test") { |state| state.tap { |value| value["resources"]["counter"] = 0 } }
    threads = 6.times.map do
      Thread.new do
        10.times do
          store.update("test") do |state|
            state["resources"]["counter"] += 1
            state
          end
        end
      end
    end
    threads.each(&:join)

    expect(store.read("test").dig("resources", "counter")).to eq(60)
    expect(store.delete("test")).to be_truthy
    expect(store.delete("test")).to be_nil
    expect(store.read("test").fetch("resources")).to be_empty
  end

  it "allows only one mutating execution per environment" do
    acquired = Queue.new
    release = Queue.new
    worker = Thread.new do
      store.with_execution_lock("test") do
        acquired << true
        release.pop
      end
    end
    acquired.pop

    expect { store.with_execution_lock("test") { nil } }
      .to raise_error(Kitsune::Kit::Errors::UnsafeOperationError, /another mutating operation/)
    release << true
    worker.join
    expect(store.with_execution_lock("test") { :acquired }).to eq(:acquired)
  end
end
