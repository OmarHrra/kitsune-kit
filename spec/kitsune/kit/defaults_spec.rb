require "spec_helper"
require "kitsune/kit/defaults"

RSpec.describe Kitsune::Kit::Defaults do
  before do
    @original_env = ENV.to_hash
    ENV.delete("SSH_KEY_ID")
  end

  after do
    ENV.replace(@original_env)
  end

  describe ".infra" do
    it "uses defaults if ENV is not set (except ssh_key_id)" do
      ENV["SSH_KEY_ID"] = "12345"
      result = described_class.infra
      expect(result[:droplet_name]).to eq("app-dev")
      expect(result[:ssh_key_id]).to eq("12345")
    end

    it "uses ENV values if present" do
      ENV["DROPLET_NAME"] = "my-app"
      ENV["REGION"] = "nyc1"
      ENV["SSH_KEY_ID"] = "abcde"

      result = described_class.infra
      expect(result[:droplet_name]).to eq("my-app")
      expect(result[:region]).to eq("nyc1")
      expect(result[:ssh_key_id]).to eq("abcde")
    end

    it "aborts if SSH_KEY_ID is missing" do
      expect {
        described_class.infra
      }.to raise_error(SystemExit)
    end
  end

  describe ".ssh" do
    it "uses default ssh config if ENV not set" do
      ENV.delete("SSH_PORT")
      ENV.delete("SSH_KEY_PATH")
  
      result = described_class.ssh
  
      expect(result[:ssh_port]).to eq("22")
      expect(result[:ssh_key_path]).to eq("~/.ssh/id_rsa")
    end
  
    it "uses ENV values for ssh config" do
      ENV["SSH_PORT"] = "2222"
      ENV["SSH_KEY_PATH"] = "/home/user/.ssh/custom_key"
  
      result = described_class.ssh
  
      expect(result[:ssh_port]).to eq("2222")
      expect(result[:ssh_key_path]).to eq("/home/user/.ssh/custom_key")
    end
  end

  describe ".postgres" do
    it "builds db name with prefix and env if POSTGRES_DB is not set" do
      ENV["KIT_ENV"] = "test"
      ENV.delete("POSTGRES_DB")

      result = described_class.postgres
      expect(result[:postgres_db]).to eq("myapp_db_test")
    end

    it "uses POSTGRES_DB if set" do
      ENV["POSTGRES_DB"] = "custom_db"
      result = described_class.postgres
      expect(result[:postgres_db]).to eq("custom_db")
    end

    it "uses defaults if ENV not set" do
      ENV.delete("POSTGRES_USER")
      ENV.delete("POSTGRES_PASSWORD")
      ENV.delete("POSTGRES_PORT")
      ENV.delete("POSTGRES_IMAGE")
      result = described_class.postgres

      expect(result[:postgres_user]).to eq("postgres")
      expect(result[:postgres_password]).to eq("secret")
      expect(result[:postgres_port]).to eq("5432")
      expect(result[:postgres_image]).to eq("postgres:17")
    end
  end

  describe ".redis" do
    it "uses default redis config if ENV not set" do
      ENV.delete("REDIS_PORT")
      ENV.delete("REDIS_PASSWORD")
      result = described_class.redis

      expect(result[:redis_port]).to eq("6379")
      expect(result[:redis_password]).to eq("secret")
    end

    it "uses ENV values for redis config" do
      ENV["REDIS_PORT"] = "6380"
      ENV["REDIS_PASSWORD"] = "securepass"
      result = described_class.redis

      expect(result[:redis_port]).to eq("6380")
      expect(result[:redis_password]).to eq("securepass")
    end
  end

  describe ".system" do
    it "uses default system config" do
      result = described_class.system
      expect(result[:swap_size_gb]).to eq(2)
      expect(result[:swap_swappiness]).to eq(10)
      expect(result[:disable_swap]).to eq(false)
    end

    it "parses ENV values correctly" do
      ENV["SWAP_SIZE_GB"] = "4"
      ENV["SWAP_SWAPPINESS"] = "60"
      ENV["DISABLE_SWAP"] = "true"

      result = described_class.system
      expect(result[:swap_size_gb]).to eq(4)
      expect(result[:swap_swappiness]).to eq(60)
      expect(result[:disable_swap]).to eq(true)
    end
  end

  describe ".metrics" do
    it "returns true if ENABLE_DO_METRICS is 'true'" do
      ENV["ENABLE_DO_METRICS"] = "true"
      expect(described_class.metrics[:enable_do_metrics]).to eq(true)
    end

    it "returns false if ENABLE_DO_METRICS is 'false'" do
      ENV["ENABLE_DO_METRICS"] = "false"
      expect(described_class.metrics[:enable_do_metrics]).to eq(false)
    end

    it "uses default if ENABLE_DO_METRICS is not set" do
      ENV.delete("ENABLE_DO_METRICS")
      expect(described_class.metrics[:enable_do_metrics]).to eq(true)
    end
  end
end
