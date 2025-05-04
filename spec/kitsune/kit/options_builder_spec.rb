require "spec_helper"
require "kitsune/kit/options_builder"

RSpec.describe Kitsune::Kit::OptionsBuilder do
  before do
    @original_env = ENV.to_hash
  end

  after do
    ENV.replace(@original_env)
  end

  let(:defaults) do
    {
      ssh_port: "22",
      ssh_key_path: "~/.ssh/id_rsa"
    }
  end

  context "with no ENV and no current options" do
    it "returns defaults" do
      result = described_class.build({}, defaults: defaults)
      expect(result).to eq(defaults)
    end
  end

  context "with ENV overrides" do
    before do
      ENV["SSH_PORT"] = "2022"
      ENV["SSH_KEY_PATH"] = "/tmp/test_rsa"
    end

    it "overrides defaults with ENV" do
      result = described_class.build({}, defaults: defaults)
      expect(result[:ssh_port]).to eq("2022")
      expect(result[:ssh_key_path]).to eq("/tmp/test_rsa")
    end
  end

  context "with current_options overrides" do
    before do
      ENV["SSH_PORT"] = "2222"
    end

    it "overrides ENV and defaults with current_options" do
      current_options = {
        "ssh_port" => "9999", # intentionally as string key
        "ssh_key_path" => "/override/key"
      }

      result = described_class.build(current_options, defaults: defaults)
      expect(result[:ssh_port]).to eq("9999")
      expect(result[:ssh_key_path]).to eq("/override/key")
    end
  end

  context "with required keys missing" do
    it "aborts if required keys are not present" do
      expect {
        described_class.build({}, required: [:ssh_key_id], defaults: {})
      }.to raise_error(SystemExit)
    end
  end
end
