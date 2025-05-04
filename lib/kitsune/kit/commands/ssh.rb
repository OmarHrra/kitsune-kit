# frozen_string_literal: true

require "thor"
require "droplet_kit"

module Kitsune
  module Kit
    module Commands
      class Ssh < Thor
        namespace "ssh"
        default_task :connect

        desc "connect", "Connect to a remote server via SSH"
        option :ip, type: :string, desc: "Server IP address (optional)"
        option :user, type: :string, default: "deploy", desc: "SSH user"
        def connect
          Kitsune::Kit::EnvLoader.load!

          ip = options[:ip] || fetch_server_ip
          user = options[:user]
          key_path = Kitsune::Kit::Defaults.ssh[:ssh_key_path]

          say "🔗 Connecting to #{user}@#{ip}...", :green
          exec "ssh -i #{key_path} -o StrictHostKeyChecking=no #{user}@#{ip}"
        end

        no_commands do
          def fetch_server_ip
            token = ENV.fetch("DO_API_TOKEN") { abort "❌ DO_API_TOKEN is missing" }

            client = DropletKit::Client.new(access_token: token)
            name = Kitsune::Kit::Defaults.infra[:droplet_name]

            droplet = client.droplets.all.find { |d| d.name == name }
            abort "❌ Droplet '#{name}' not found on DigitalOcean" unless droplet

            ip = droplet.networks.v4.find { |n| n.type == "public" }&.ip_address
            abort "❌ No public IP found for droplet '#{name}'" unless ip

            ip
          end
        end
      end
    end
  end
end
