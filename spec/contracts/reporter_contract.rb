# frozen_string_literal: true

RSpec.shared_examples "an event reporter" do
  it "consumes a versioned domain event without changing it" do
    before = event.to_h

    expect { reporter.handle(event) }.not_to raise_error
    expect(event.to_h).to eq(before)
  end
end
