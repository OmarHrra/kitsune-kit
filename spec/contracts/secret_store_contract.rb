# frozen_string_literal: true

RSpec.shared_examples "a secret store" do
  it "reports and fetches configured values" do
    expect(secret_store.configured?("TOKEN")).to be(true)
    expect(secret_store.fetch(:TOKEN)).to eq("top-secret")
  end

  it "raises a typed actionable error for a missing required value" do
    expect { secret_store.fetch("MISSING") }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError) { |error|
        expect(error.hint).not_to be_empty
      }
  end

  it "returns an empty value when a missing secret is explicitly optional" do
    expect(secret_store.configured?("MISSING")).to be(false)
    expect(secret_store.fetch("MISSING", required: false)).to eq("")
  end
end
