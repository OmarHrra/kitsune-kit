# frozen_string_literal: true

require "spec_helper"
require_relative "../contracts/provider_contract"

RSpec.describe Kitsune::Kit::Adapters::FakeProvider do
  let(:provider) { described_class.new }
  let(:unauthorized_provider) do
    described_class.new(
      failures: {
        validate_credentials: Kitsune::Kit::Errors::AuthenticationError.new("rejected", retryable: false)
      }
    )
  end
  let(:timeout_provider) do
    described_class.new(failures: { wait_until_ready: Kitsune::Kit::Errors::TimeoutError.new("deadline") })
  end

  it_behaves_like "a provider adapter"
end
