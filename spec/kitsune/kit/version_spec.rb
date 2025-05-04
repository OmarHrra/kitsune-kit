require "spec_helper"

RSpec.describe Kitsune::Kit do
  it "has a version number" do
    expect(Kitsune::Kit::VERSION).not_to be_nil
  end
end
