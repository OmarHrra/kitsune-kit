# frozen_string_literal: true

RSpec.shared_examples "a state store" do
  it "returns an isolated versioned empty state and persists atomic-style updates" do
    first = state_store.read("test")
    first["resources"]["server"] = { "id" => "mutated-copy" }
    expect(state_store.read("test")["resources"]).to be_empty

    updated = state_store.update("test") do |state|
      state["resources"]["server"] = { "id" => "server-1" }
      state
    end
    expect(updated).to include("version" => 1, "environment" => "test")
    expect(updated["updated_at"]).not_to be_nil
    expect(state_store.read("test").dig("resources", "server", "id")).to eq("server-1")
  end

  it "validates writes and deletes idempotently" do
    invalid = state_store.read("test").merge("version" => 99)
    expect { state_store.write("test", invalid) }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /unsupported state schema version/)
    expect { state_store.read("../../outside") }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /environment name/)

    state_store.update("test") { |state| state }
    expect(state_store.delete("test")).to be(true)
    expect(state_store.delete("test")).to be_nil
    expect(state_store.read("test")["resources"]).to be_empty
  end

  it "refuses a concurrent mutating execution for the same environment" do
    entered = Queue.new
    release = Queue.new
    owner = Thread.new do
      state_store.with_execution_lock("test") do
        entered << true
        release.pop
      end
    end
    entered.pop

    expect { state_store.with_execution_lock("test") { nil } }
      .to raise_error(Kitsune::Kit::Errors::UnsafeOperationError, /another mutating operation/)
  ensure
    release << true if release
    owner&.join
  end
end
