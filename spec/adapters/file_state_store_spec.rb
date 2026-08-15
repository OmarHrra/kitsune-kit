# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "spec_helper"
require_relative "../contracts/state_store_contract"

RSpec.describe Kitsune::Kit::StateStore do
  let(:root) { Dir.mktmpdir("kitsune-state-contract") }
  let(:state_store) { described_class.new(root: root) }

  after { FileUtils.remove_entry(root) }

  it_behaves_like "a state store"
end
