# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "spec_helper"

RSpec.describe "plan and apply workflows" do
  let(:root) { Dir.mktmpdir("kitsune-workflow") }
  let(:config) { build_config }
  let(:provider) { Kitsune::Kit::Adapters::FakeProvider.new }
  let(:store) { Kitsune::Kit::StateStore.new(root: root) }
  let(:operation) { Kitsune::Kit::Operations::EnsureServer.new(config: config, provider: provider, state_store: store) }
  let(:events) { [] }
  let(:bus) { Kitsune::Kit::Events::Bus.new.tap { |value| value.subscribe { |event| events << event } } }

  after { FileUtils.remove_entry(root) }

  it "builds a non-mutating plan and emits stable events" do
    result = Kitsune::Kit::Workflows::BuildPlan.new(config: config, operations: [operation], event_bus: bus).call

    expect(result).to be_success
    expect(result.value.changed_count).to eq(1)
    expect(provider.servers).to be_empty
    expect(events.map(&:type)).to eq(%w[run_started plan_built run_finished])
  end

  it "uses the injected clock for deterministic event times and durations" do
    clock = Kitsune::Kit::Adapters::FakeClock.new(now: Time.utc(2026, 8, 13, 12), monotonic: 10.0)
    timed_operation = Struct.new(:resource) do
      define_method(:plan) do
        clock.advance(1.25)
        Kitsune::Kit::Change.new(resource: resource, action: "create", summary: "Create #{resource}")
      end
    end.new("timed")

    Kitsune::Kit::Workflows::BuildPlan.new(
      config: config, operations: [timed_operation], event_bus: bus, clock: clock
    ).call

    expected_times = [
      "2026-08-13T12:00:00.000000Z",
      "2026-08-13T12:00:01.250000Z",
      "2026-08-13T12:00:01.250000Z"
    ]
    expect(events.map(&:time)).to eq(expected_times)
    expect(events.last.data[:duration_ms]).to eq(1_250)
  end

  it "uses the injected clock when persisting apply run journals" do
    clock = Kitsune::Kit::Adapters::FakeClock.new(now: Time.utc(2026, 8, 13, 12))

    result = Kitsune::Kit::Workflows::ApplyPlan.new(
      config: config, operations: [operation], state_store: store, clock: clock
    ).call

    run = store.read(config.environment)["runs"].fetch(result.metadata[:run_id])
    expected_times = ["2026-08-13T12:00:00.000000Z", "2026-08-13T12:00:00.000000Z"]
    expect(run.values_at("started_at", "finished_at")).to eq(expected_times)
  end

  it "applies the exact plan and emits operation progress" do
    plan = Kitsune::Kit::Workflows::BuildPlan.new(config: config, operations: [operation]).call.value

    result = Kitsune::Kit::Workflows::ApplyPlan.new(
      config: config,
      operations: [operation],
      event_bus: bus
    ).call(plan: plan)

    expect(result).to be_success
    expect(provider.servers.one?).to be(true)
    expect(events.map(&:type)).to include("operation_started", "operation_progressed", "operation_succeeded")
    expect(events.select { |event| event.type == "operation_progressed" }.map { |event| event.data[:percent] })
      .to eq([0, 100])
  end

  it "emits failure and preserves the domain error" do
    failure = Kitsune::Kit::Errors::ProviderError.new("provider unavailable")
    failing_provider = Kitsune::Kit::Adapters::FakeProvider.new(failures: { create_server: failure })
    failing_operation = Kitsune::Kit::Operations::EnsureServer.new(
      config: config,
      provider: failing_provider,
      state_store: store
    )

    expect do
      Kitsune::Kit::Workflows::ApplyPlan.new(
        config: config,
        operations: [failing_operation],
        event_bus: bus
      ).call
    end.to raise_error(Kitsune::Kit::Errors::ProviderError)
    expect(events.map(&:type)).to include("operation_failed", "run_finished")
    guidance = events.find { |event| event.type == "warning_emitted" }
    expect(guidance.data[:message]).to include("No step was confirmed", "kit resume")
  end

  it "records a failed run and resumes only unfinished operations" do
    calls = []
    failure = true
    operation_class = Class.new do
      attr_reader :resource

      define_method(:initialize) do |resource, action|
        @resource = resource
        @action = action
      end

      define_method(:plan) do
        Kitsune::Kit::Change.new(resource: resource, action: "create", summary: "Create #{resource}")
      end

      define_method(:apply) do |_change|
        calls << resource
        raise Kitsune::Kit::Errors::ProviderError, "temporary failure" if @action.call

        resource
      end
    end
    first = operation_class.new("first", -> { false })
    second = operation_class.new("second", -> { failure })

    expect do
      Kitsune::Kit::Workflows::ApplyPlan.new(
        config: config,
        operations: [first, second],
        state_store: store,
        event_bus: bus
      ).call
    end.to raise_error(Kitsune::Kit::Errors::ProviderError)

    failed_id, failed_run = store.read(config.environment)["runs"].first
    expect(failed_run["status"]).to eq("failure")
    expect(failed_run.dig("steps", "first", "status")).to eq("success")
    expect(failed_run.dig("steps", "second", "status")).to eq("failure")
    guidance = events.find { |event| event.type == "warning_emitted" }
    expect(guidance.data[:message]).to include("Last confirmed step: first", "kit resume #{failed_id}")

    failure = false
    result = Kitsune::Kit::Workflows::ApplyPlan.new(
      config: config,
      operations: [first, second],
      state_store: store,
      event_bus: bus
    ).call(resume_from: failed_id)

    expect(result).to be_success
    expect(result.metadata[:resumed_from]).to eq(failed_id)
    expect(calls).to eq(%w[first second second])
    expect(events.map(&:type)).to include("operation_skipped")
    resumed_run = store.read(config.environment)["runs"].fetch(result.metadata[:run_id])
    expect(resumed_run["status"]).to eq("success")
    expect(resumed_run["resumed_from"]).to eq(failed_id)
  end

  it "marks cancellation without corrupting the resumable plan" do
    cancellation = Kitsune::Kit::Cancellation.new.tap(&:cancel!)

    expect do
      Kitsune::Kit::Workflows::ApplyPlan.new(
        config: config,
        operations: [operation],
        state_store: store,
        cancellation: cancellation
      ).call
    end.to raise_error(Kitsune::Kit::Cancellation::Cancelled)

    run = store.read(config.environment)["runs"].values.last
    expect(run["status"]).to eq("cancelled")
    expect(run["changes"]).not_to be_empty
  end

  it "rejects a completed run and an incompatible saved operation set" do
    result = Kitsune::Kit::Workflows::ApplyPlan.new(
      config: config,
      operations: [operation],
      state_store: store
    ).call

    expect do
      Kitsune::Kit::Workflows::ApplyPlan.new(
        config: config,
        operations: [operation],
        state_store: store
      ).call(resume_from: result.metadata[:run_id])
    end.to raise_error(Kitsune::Kit::Errors::ConfigurationError, /cannot be resumed/)

    store.update(config.environment) do |state|
      state["runs"]["incompatible"] = {
        "status" => "failure",
        "changes" => [{ "resource" => "missing", "action" => "create", "summary" => "Missing" }],
        "steps" => {}
      }
      state
    end
    expect do
      Kitsune::Kit::Workflows::ApplyPlan.new(
        config: config,
        operations: [operation],
        state_store: store
      ).call(resume_from: "incompatible")
    end.to raise_error(Kitsune::Kit::Errors::ConfigurationError, /does not match/)
  end
end
