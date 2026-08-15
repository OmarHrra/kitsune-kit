# frozen_string_literal: true

require "spec_helper"

RSpec.describe "domain values and event delivery" do
  it "rejects unknown result states and plan actions" do
    expect { Kitsune::Kit::Result.new(status: :unknown) }.to raise_error(ArgumentError, /unknown status/)
    expect { Kitsune::Kit::Change.new(resource: "x", action: "replace", summary: "x") }
      .to raise_error(ArgumentError, /unknown action/)
  end

  it "exposes stable status predicates and plan counts" do
    failure = Kitsune::Kit::Result.new(status: :failure)
    cancelled = Kitsune::Kit::Result.new(status: :cancelled)
    plan = Kitsune::Kit::Plan.new(
      environment: :test,
      changes: [
        Kitsune::Kit::Change.new(resource: "a", action: :create, summary: "A"),
        Kitsune::Kit::Change.new(resource: "b", action: :no_change, summary: "B")
      ]
    )

    expect(failure).to be_failure
    expect(cancelled).to be_cancelled
    expect(plan).to be_changed
    expect(plan.counts).to eq("create" => 1, "no_change" => 1)
  end

  it "requires subscribers and delivers to callable and handler objects" do
    bus = Kitsune::Kit::Events::Bus.new
    expect { bus.subscribe }.to raise_error(ArgumentError, /subscriber or block/)
    received = []
    handler = Struct.new(:received) do
      def handle(event) = received << event.type
    end.new(received)
    bus.subscribe(handler)
    bus.subscribe { |event| received << "call:#{event.type}" }

    event = Kitsune::Kit::Events::Event.build("test", run_id: "run", time: Time.utc(2026), value: 1)
    expect(bus.publish(event)).to equal(event)
    expect(received).to eq(["test", "call:test"])
    expect(event.to_h).to include(schema_version: 1, type: "test", run_id: "run", data: { value: 1 })
  end

  it "maps every stable domain error and unknown failures to documented exit statuses" do
    expected = {
      Kitsune::Kit::Errors::ConfigurationError => 3,
      Kitsune::Kit::Errors::AuthenticationError => 4,
      Kitsune::Kit::Errors::ProviderError => 5,
      Kitsune::Kit::Errors::ConnectionError => 6,
      Kitsune::Kit::Errors::RemoteCommandError => 7,
      Kitsune::Kit::Errors::VerificationError => 8,
      Kitsune::Kit::Errors::UnsafeOperationError => 9,
      Kitsune::Kit::Errors::TimeoutError => 10
    }

    expected.each do |error_class, status|
      error = error_class.new("test")
      expect(Kitsune::Kit::Errors.exit_status(error)).to eq(status)
      expect(error.hint).not_to be_empty
    end
    expect(Kitsune::Kit::Errors.exit_status(StandardError.new("test"))).to eq(1)
  end
end
