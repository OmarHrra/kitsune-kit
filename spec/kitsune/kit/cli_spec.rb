require "spec_helper"
require "kitsune/kit/cli"

RSpec.describe "bin/kit CLI", type: :integration do
  let(:bin_path) { File.expand_path("../../../../bin/kit", __FILE__) }
  let(:expected_version) { "Kitsune Kit v#{Kitsune::Kit::VERSION}" }

  it "prints version with -v" do
    output = `#{bin_path} -v`.strip
    expect(output).to eq(expected_version)
  end

  it "prints version with --version" do
    output = `#{bin_path} --version`.strip
    expect(output).to eq(expected_version)
  end

  it "prints version with version subcommand" do
    output = `#{bin_path} version`.strip
    expect(output).to eq(expected_version)
  end
end