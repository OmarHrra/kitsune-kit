# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "spec_helper"

RSpec.describe Kitsune::Kit::Workflows::EnvironmentSelection do
  let(:root) { Dir.mktmpdir("kitsune-environments") }
  subject(:selection) { described_class.new(root: root) }

  before do
    directory = File.join(root, ".kitsune/environments")
    FileUtils.mkdir_p(directory)
    File.write(File.join(directory, "production.yml"), "version: 1\n")
    File.write(File.join(directory, "staging.yml"), "version: 1\n")
  end

  after { FileUtils.remove_entry(root) }

  it "lists, selects and reads an environment atomically" do
    expect(selection.list).to eq(%w[production staging])
    expect(selection.use("production")).to eq("production")
    expect(selection.current(env: {})).to eq("production")
    expect(File.stat(File.join(root, ".kitsune/environment")).mode & 0o777).to eq(0o600)
  end

  it "gives KITSUNE_ENV precedence without changing the persisted selection" do
    selection.use("production")

    expect(selection.current(env: { "KITSUNE_ENV" => "staging" })).to eq("staging")
    expect(selection.current(env: {})).to eq("production")
  end

  it "rejects traversal and unknown environments" do
    expect { selection.use("../production") }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /invalid format/)
    expect { selection.use("missing") }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /does not exist/)
  end
end
