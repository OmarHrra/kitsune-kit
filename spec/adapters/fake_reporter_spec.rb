# frozen_string_literal: true

require "spec_helper"

RSpec.describe Kitsune::Kit::Adapters::FakeReporter do
  subject(:reporter) { described_class.new }

  it "captures, filters and clears workflow events without presentation dependencies" do
    started = Kitsune::Kit::Events::Event.build("run_started", run_id: "run-1", command: "plan")
    finished = Kitsune::Kit::Events::Event.build("run_finished", run_id: "run-1", status: "success")

    expect(reporter.handle(started)).to equal(started)
    reporter.handle(finished)

    expect(reporter.events).to eq([started, finished])
    expect(reporter.events_of(:run_finished)).to eq([finished])
    expect(reporter.clear).to equal(reporter)
    expect(reporter.events).to be_empty
  end

  it "can subscribe directly to the domain event bus" do
    bus = Kitsune::Kit::Events::Bus.new
    bus.subscribe(reporter)
    event = Kitsune::Kit::Events::Event.build("warning_emitted", run_id: "run-2", message: "retry")

    expect { bus.publish(event) }.to change { reporter.events.length }.from(0).to(1)
  end
end
