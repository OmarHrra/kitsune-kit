module Kitsune
  module Kit
    module Defaults
      DROPLET = {
        droplet_name: "app-dev",
        region: "sfo3",
        size: "s-1vcpu-1gb",
        image: "ubuntu-22-04-x64",
        tag: "rails-dev"
      }.freeze

      SSH = {
        ssh_port: "22",
        ssh_key_path: "~/.ssh/id_rsa"
      }.freeze

      POSTGRES = {
        user: "postgres",
        password: "secret",
        port: "5432",
        image: "postgres:17"
      }.freeze

      SYSTEM = {
        swap_size_gb: 2,
        swap_swappiness: 10,
        disable_swap: false
      }.freeze

      METRICS = {
        enable_do_metrics: true
      }.freeze

      REDIS = {
        port: "6379",
        password: "secret"
      }.freeze

      def self.infra
        {
          droplet_name: ENV.fetch('DROPLET_NAME', DROPLET[:droplet_name]),
          region: ENV.fetch('REGION', DROPLET[:region]),
          size: ENV.fetch('SIZE', DROPLET[:size]),
          image: ENV.fetch('IMAGE', DROPLET[:image]),
          tag: ENV.fetch('TAG_NAME', DROPLET[:tag]),
          ssh_key_id: ENV.fetch('SSH_KEY_ID') { abort "❌ Missing SSH_KEY_ID" }
        }
      end

      def self.ssh
        {
          ssh_port: ENV.fetch('SSH_PORT', SSH[:ssh_port]),
          ssh_key_path: ENV.fetch('SSH_KEY_PATH', SSH[:ssh_key_path])
        }
      end

      def self.postgres
        env = ENV.fetch('KIT_ENV', 'development')

        {
          postgres_db: ENV.fetch('POSTGRES_DB') { "myapp_db_#{env}" },
          postgres_user: ENV.fetch('POSTGRES_USER', POSTGRES[:user]),
          postgres_password: ENV.fetch('POSTGRES_PASSWORD', POSTGRES[:password]),
          postgres_port: ENV.fetch('POSTGRES_PORT', POSTGRES[:port]),
          postgres_image: ENV.fetch('POSTGRES_IMAGE', POSTGRES[:image])
        }
      end

      def self.redis
        {
          redis_port: ENV.fetch("REDIS_PORT", REDIS[:port]),
          redis_password: ENV.fetch("REDIS_PASSWORD", REDIS[:password])
        }
      end

      def self.system
        {
          swap_size_gb: ENV.fetch("SWAP_SIZE_GB", SYSTEM[:swap_size_gb]).to_i,
          swap_swappiness: ENV.fetch("SWAP_SWAPPINESS", SYSTEM[:swap_swappiness]).to_i,
          disable_swap: ENV.fetch("DISABLE_SWAP", SYSTEM[:disable_swap].to_s) == "true"
        }
      end

      def self.metrics
        {
          enable_do_metrics: ENV.fetch("ENABLE_DO_METRICS", METRICS[:enable_do_metrics].to_s) == "true"
        }
      end
    end
  end
end
