module Kitsune
  module Kit
    module Defaults
      DROPLET = {
        droplet_name: "app-prod",
        region: "sfo3",
        size: "s-1vcpu-1gb",
        image: "ubuntu-22-04-x64",
        tag: "rails-prod"
      }.freeze

      SSH = {
        ssh_port: "22",
        ssh_key_path: "~/.ssh/id_rsa"
      }.freeze

      POSTGRES = {
        db_prefix: "myapp_db",
        user: "postgres",
        password: "secret",
        port: "5432",
        image: "postgres:15"
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
          postgres_db: ENV.fetch('POSTGRES_DB') { "#{POSTGRES[:db_prefix]}_#{env}" },
          postgres_user: ENV.fetch('POSTGRES_USER', POSTGRES[:user]),
          postgres_password: ENV.fetch('POSTGRES_PASSWORD', POSTGRES[:password]),
          postgres_port: ENV.fetch('POSTGRES_PORT', POSTGRES[:port]),
          postgres_image: ENV.fetch('POSTGRES_IMAGE', POSTGRES[:image])
        }
      end
    end
  end
end
