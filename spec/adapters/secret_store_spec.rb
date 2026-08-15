# frozen_string_literal: true

require "spec_helper"
require_relative "../contracts/secret_store_contract"

RSpec.describe "secret store adapters" do
  context "with the environment adapter" do
    let(:secret_store) { Kitsune::Kit::SecretStores::Environment.new(env: { "TOKEN" => "top-secret" }) }

    it_behaves_like "a secret store"
  end

  context "with the in-memory fake" do
    let(:secret_store) { Kitsune::Kit::Adapters::FakeSecretStore.new("TOKEN" => "top-secret") }

    it_behaves_like "a secret store"

    it "can change a value and records reads for workflow assertions" do
      secret_store.set(:TOKEN, "replacement")

      expect(secret_store.fetch("TOKEN")).to eq("replacement")
      expect(secret_store.fetches).to eq(["TOKEN"])
    end
  end
end
