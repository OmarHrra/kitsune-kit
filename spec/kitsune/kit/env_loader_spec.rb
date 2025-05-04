require "spec_helper"
require "kitsune/kit/env_loader"

RSpec.describe Kitsune::Kit::EnvLoader do
  let(:env_path) { ".kitsune/infra.test.env" }
  let(:kit_env_path) { ".kitsune/kit.env" }

  before do
    FileUtils.mkdir_p(".kitsune")
    File.write(env_path, "FOO=bar\n")
    File.write(kit_env_path, "KIT_ENV=test")
    ENV.delete("FOO")
    ENV.delete("KIT_ENV")
    described_class.instance_variable_set(:@loaded, false)
  end

  after do
    File.delete(env_path) if File.exist?(env_path)
    File.delete(kit_env_path) if File.exist?(kit_env_path)
    described_class.instance_variable_set(:@loaded, false)
    ENV.delete("FOO")
    ENV.delete("KIT_ENV")
  end

  it "loads the correct environment file based on .kitsune/kit.env" do
    expect {
      described_class.load!
    }.to output(/Loaded Kitsune environment from/).to_stdout

    expect(ENV["FOO"]).to eq("bar")
  end

  it "respects ENV['KIT_ENV'] when present" do
    ENV["KIT_ENV"] = "test"
    File.write(".kitsune/infra.test.env", "BAZ=qux\n")

    expect {
      described_class.load!
    }.to output(/infra.test.env/).to_stdout

    expect(ENV["BAZ"]).to eq("qux")
  end

  it "does nothing if no env files exist" do
    File.delete(env_path)
    File.delete(kit_env_path)

    expect {
      described_class.load!
    }.to output(/No Kitsune infra config found/).to_stdout
  end

  it "does not reload twice" do
    described_class.load!
    expect {
      described_class.load!
    }.not_to output.to_stdout
  end
end
