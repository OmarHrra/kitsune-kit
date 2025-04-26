require "thor"
require "open3"

module Kitsune
  module Kit
    module Commands
      class Bootstrap < Thor
        namespace "bootstrap"

        class_option :rollback, type: :boolean, default: false, desc: "Rollback the setup"
        class_option :keep_server, type: :boolean, default: false, desc: "Keep server after rollback"
        class_option :ssh_port, type: :string, default: ENV['SSH_PORT'] || '22', desc: "SSH port for server"
        class_option :ssh_key_path, type: :string, default: ENV['SSH_KEY_PATH'] || '~/.ssh/id_rsa', desc: "SSH private key path"

        desc "execute", "Run the full bootstrap process or rollback"
        def execute
          if options[:rollback]
            say "🔄 Rolling back server configurations...", :yellow
            rollback_sequence
          else
            say "🏗️ Setting up server from scratch...", :green
            setup_sequence
          end
        
          say "🎉 Done!", :green
        end

        no_commands do
          def setup_sequence
            droplet_ip = fetch_droplet_ip

            say "→ Droplet IP: #{droplet_ip}", :cyan

            run_cli("setup_user create", droplet_ip)
            run_cli("setup_firewall create", droplet_ip)
            run_cli("setup_unattended create", droplet_ip)
          end

          def rollback_sequence
            droplet_ip = fetch_droplet_ip

            say "→ Using Droplet IP: #{droplet_ip}", :cyan

            if ssh_accessible?(droplet_ip)
              run_cli("setup_unattended rollback", droplet_ip)
              run_cli("setup_firewall rollback", droplet_ip)
            else
              say "⏭️  Skipping unattended-upgrades and firewall rollback (no deploy user)", :yellow
            end

            run_cli("setup_user:rollback", droplet_ip)

            unless options[:keep_server]
              run_cli("provision rollback", droplet_ip)
            else
              say "⏭️  Skipping droplet deletion (--keep-server enabled)", :yellow
            end
          end

          def fetch_droplet_ip
            output, status = Open3.capture2e("bin/kit provision create")
            unless status.success?
              abort "❌ Error fetching or creating droplet"
            end

            ip = output.match(/(\d{1,3}\.){3}\d{1,3}/).to_s
            abort "❌ Could not detect droplet IP!" if ip.empty?
            ip
          end

          def run_cli(command, droplet_ip)
            args = [
              "bin/kit",
              command,
              "--server-ip", droplet_ip,
              "--ssh-port", options[:ssh_port],
              "--ssh-key-path", options[:ssh_key_path]
            ]

            full_command = args.join(' ')
            say "▶️ Running: #{full_command}", :blue
            system(full_command) || abort("❌ Command failed: #{full_command}")
          end

          def ssh_accessible?(droplet_ip)
            system("ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -p #{options[:ssh_port]} -i #{File.expand_path(options[:ssh_key_path])} deploy@#{droplet_ip} true", out: File::NULL, err: File::NULL)
          end
        end
      end
    end
  end
end
