# frozen_string_literal: true

RSpec.describe Kitsune::Kit do
  it "exposes the release version" do
    expect(described_class::VERSION).to eq("0.6.0")
  end
end
