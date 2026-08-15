# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "spec_helper"

RSpec.describe Kitsune::Kit::Workflows::InitializeProject do
  let(:root) { Dir.mktmpdir("kitsune-init") }
  subject(:workflow) { described_class.new(root: root) }

  after { FileUtils.remove_entry(root) }

  it "creates secure configuration and gitignore entries" do
    files = workflow.call

    expect(files).to contain_exactly(
      File.join(root, ".kitsune/config.yml"),
      File.join(root, ".kitsune/environments/development.yml"),
      File.join(root, ".kitsune/environment")
    )
    expect(File.stat(files.first).mode & 0o777).to eq(0o600)
    expect(File.read(File.join(root, ".gitignore"))).to include(
      "/.kitsune/state/", "/.kitsune/logs/", "/.kitsune/environment", "/.kitsune/known_hosts"
    )
  end

  it "does not overwrite existing configuration without force" do
    workflow.call

    expect { workflow.call }.to raise_error(Kitsune::Kit::Errors::UnsafeOperationError)
  end
end
