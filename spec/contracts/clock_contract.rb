# frozen_string_literal: true

RSpec.shared_examples "a clock" do
  it "provides UTC wall time and nondecreasing monotonic time" do
    wall = clock.now
    before = clock.monotonic
    clock.sleep(0)

    expect(wall).to be_a(Time)
    expect(wall.utc_offset).to eq(0)
    expect(clock.monotonic).to be >= before
  end
end
