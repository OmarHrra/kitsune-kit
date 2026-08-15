# frozen_string_literal: true

require "spec_helper"
require_relative "../contracts/state_store_contract"

RSpec.describe Kitsune::Kit::Adapters::FakeStateStore do
  let(:state_store) { described_class.new }

  it_behaves_like "a state store"
end
