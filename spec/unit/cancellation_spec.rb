# frozen_string_literal: true

require "spec_helper"

RSpec.describe Kitsune::Kit::Cancellation do
  subject(:cancellation) { described_class.new }

  it "can be checked before and after cancellation" do
    expect(cancellation).not_to be_cancelled
    expect { cancellation.check! }.not_to raise_error

    cancellation.cancel!

    expect(cancellation).to be_cancelled
    expect { cancellation.check! }.to raise_error(Kitsune::Kit::Cancellation::Cancelled)
  end
end
