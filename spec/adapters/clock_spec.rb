# frozen_string_literal: true

require "spec_helper"
require_relative "../contracts/clock_contract"

RSpec.describe "clock adapters" do
  context "with the system clock" do
    let(:clock) { Kitsune::Kit::Clock.new }

    it_behaves_like "a clock"
  end

  context "with the deterministic fake" do
    let(:clock) { Kitsune::Kit::Adapters::FakeClock.new }

    it_behaves_like "a clock"

    it "advances wall and monotonic time without blocking" do
      before = clock.now

      expect(clock.advance(2.5)).to equal(clock)
      expect(clock.now - before).to eq(2.5)
      expect(clock.monotonic).to eq(2.5)
      expect(clock.sleep(1.5)).to eq(1.5)
      expect(clock.sleeps).to eq([1.5])
      expect(clock.monotonic).to eq(4.0)
    end
  end
end
