# frozen_string_literal: true

require "spec_helper"

RSpec.describe Kitsune::Kit::SecretFilter do
  subject(:filter) { described_class.new(%w[token-123 password-456]) }

  it "redacts registered values from arbitrary text" do
    expect(filter.filter("token=token-123 password=password-456")).to eq("token=[REDACTED] password=[REDACTED]")
  end

  it "redacts values under sensitive hash keys" do
    expect(filter.filter({ token: "not-registered", nested: { password: "also-secret" } })).to eq(
      { token: "[REDACTED]", nested: { password: "[REDACTED]" } }
    )
  end

  it "redacts passwords embedded in URLs" do
    expect(filter.filter("failed for postgres://user:hidden@example.test/db; retry")).to eq(
      "failed for postgres://user:[REDACTED]@example.test/db; retry"
    )
  end

  it "redacts complete private-key blocks even when they were not registered" do
    key = "-----BEGIN OPENSSH PRIVATE KEY-----\nprivate-material\n-----END OPENSSH PRIVATE KEY-----"

    expect(filter.filter("received #{key} unexpectedly")).to eq("received [REDACTED] unexpectedly")
  end
end
