# frozen_string_literal: true

require "spec_helper"

RSpec.describe Kitsune::Kit::SecretStores::Environment do
  let(:filter) { Kitsune::Kit::SecretFilter.new }
  subject(:store) { described_class.new(env: { "TOKEN" => "top-secret" }, filter: filter) }

  it "fetches and registers configured secrets for redaction" do
    expect(store.fetch("TOKEN")).to eq("top-secret")
    expect(filter.filter("value=top-secret")).to eq("value=[REDACTED]")
  end

  it "raises an actionable error for a missing required secret" do
    expect { store.fetch("MISSING") }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError) { |error| expect(error.hint).to include("MISSING") }
  end

  it "supports optional secrets" do
    expect(store.fetch("MISSING", required: false)).to eq("")
  end
end
