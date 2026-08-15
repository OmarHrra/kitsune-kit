# frozen_string_literal: true

require "spec_helper"
require_relative "../contracts/transport_contract"

RSpec.describe Kitsune::Kit::Adapters::FakeTransport do
  let(:transport) do
    described_class.new.tap do |value|
      value.stub("printf", arguments: ["safe-value"], stdout: "safe-value")
    end
  end
  let(:unreachable_transport) { described_class.new(reachable: false) }
  let(:timeout_transport) do
    described_class.new(failures: { execute: Kitsune::Kit::Errors::TimeoutError.new("deadline") })
  end

  it_behaves_like "a transport adapter"
end
