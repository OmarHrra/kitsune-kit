# frozen_string_literal: true

require "stringio"
require "spec_helper"
require_relative "../contracts/reporter_contract"

RSpec.describe "reporter adapters" do
  let(:event) do
    Kitsune::Kit::Events::Event.build("warning_emitted", run_id: "contract", message: "inspect")
  end

  context "with the human reporter" do
    let(:reporter) { Kitsune::Kit::Reporters::Human.new(output: StringIO.new, error: StringIO.new, color: false) }

    it_behaves_like "an event reporter"
  end

  context "with the JSON reporter" do
    let(:reporter) { Kitsune::Kit::Reporters::Json.new(output: StringIO.new) }

    it_behaves_like "an event reporter"
  end

  context "with the in-memory fake" do
    let(:reporter) { Kitsune::Kit::Adapters::FakeReporter.new }

    it_behaves_like "an event reporter"
  end
end
