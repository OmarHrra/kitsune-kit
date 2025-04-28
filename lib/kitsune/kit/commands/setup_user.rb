require "thor"
require "net/ssh"
require_relative "../defaults"
require_relative "../options_builder"

module Kitsune
  module Kit
    module Commands
      class SetupUser < Thor
        namespace "setup_user"

        class_option :server_ip,    aliases: "-s", required: true, desc: "Server IP address or hostname"
        class_option :ssh_port,     aliases: "-p", desc: "SSH port"
        class_option :ssh_key_path, aliases: "-k", desc: "Path to your private SSH key"

        desc "create",   "Create and configure 'deploy' user on remote server"
        def create
          filled_options = Kitsune::Kit::OptionsBuilder.build(
            options,
            required: [:server_ip],
            defaults: Kitsune::Kit::Defaults.ssh
          )

          with_ssh_connection(false, filled_options) do |ssh|
            perform_setup(ssh)
          end
        end

        desc "rollback", "Revert configuration and remove 'deploy' user from remote server"
        def rollback
          filled_options = Kitsune::Kit::OptionsBuilder.build(
            options,
            required: [:server_ip],
            defaults: Kitsune::Kit::Defaults.ssh
          )

          server = filled_options[:server_ip]
          port   = filled_options[:ssh_port]
          key    = File.expand_path(filled_options[:ssh_key_path])

          # First, attempt SSH config restore as 'deploy'
          begin
            with_ssh_connection(true, filled_options) do |ssh|
              perform_rollback_config(ssh)
            end
          rescue StandardError => e
            say "⚠️ Skipping SSH config restore: #{e.message}", :yellow
          end

          # Then reconnect as 'root' to remove sudoers and delete user
          say "🔑 Reconnecting as root@#{server}:#{port}", :green
          Net::SSH.start(server, 'root', port: port, keys: [key], non_interactive: true) do |ssh|
            perform_rollback_cleanup(ssh)
          end
          say "✅ Rollback completed", :green
        end

        no_commands do
          def with_ssh_connection(rollback, filled_options)
            server = filled_options[:server_ip]
            port   = filled_options[:ssh_port]
            key    = File.expand_path(filled_options[:ssh_key_path])
          
            user = rollback ? 'deploy' : detect_remote_user(server, port, key)
            say "🔑 Connecting as #{user}@#{server}:#{port}", :green
          
            Net::SSH.start(server, user, port: port, keys: [key], non_interactive: true, timeout: 5) do |ssh|
              yield ssh
            end
          end

          def detect_remote_user(server, port, key)
            %w[deploy root].each do |u|
              begin
                Net::SSH.start(server, u, port: port, keys: [key], non_interactive: true, timeout: 5) { }
                say "✔️ Able to SSH as #{u}", :green
                return u
              rescue
                next
              end
            end
            abort("❌ Could not connect as deploy or root on #{server}:#{port}")
          end

          def perform_setup(ssh)
            output = ssh.exec! <<~'EOH'
              set -e

              echo "✍🏻 Creating deploy user…"
              if ! id deploy &>/dev/null; then
                if command -v adduser &>/dev/null; then
                  sudo adduser --disabled-password --gecos "" deploy && echo "   - user 'deploy' created"
                else
                  sudo useradd -m -s /bin/bash deploy && echo "   - user 'deploy' created"
                fi
                sudo usermod -aG sudo deploy && echo "   - 'deploy' added to sudo"
              else
                echo "   - user 'deploy' already exists"
              fi

              echo "✍🏻 Configuring passwordless sudo…"
              if [ ! -f /etc/sudoers.d/deploy ]; then
                echo 'deploy ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/deploy \
                  && sudo chmod 440 /etc/sudoers.d/deploy \
                  && echo "   - sudoers entry created"
              else
                echo "   - sudoers entry exists"
              fi

              echo "✍🏻 Backing up SSH config…"
              sudo test -f /etc/ssh/sshd_config.bak || sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak && echo "   - sshd_config backed up"

              echo "✍🏻 Hardening SSH…"
              grep -q '^PermitRootLogin no' /etc/ssh/sshd_config \
                || sudo sed -i 's/^#*PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config && echo "   - PermitRootLogin no"
              grep -q '^PasswordAuthentication no' /etc/ssh/sshd_config \
                || sudo sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config && echo "   - PasswordAuthentication no"
              sudo systemctl restart sshd && echo "   - sshd restarted"

              echo "✍🏻 Installing SSH keys for deploy…"
              if [ ! -f /home/deploy/.ssh/authorized_keys ]; then
                sudo mkdir -p /home/deploy/.ssh
                sudo cp /root/.ssh/authorized_keys /home/deploy/.ssh/authorized_keys
                sudo chown -R deploy:deploy /home/deploy/.ssh
                sudo chmod 700 /home/deploy/.ssh
                sudo chmod 600 /home/deploy/.ssh/authorized_keys
                echo "   - authorized_keys copied"
              else
                echo "   - authorized_keys already present"
              fi
            EOH
            say output
            say "✅ Setup completed", :green
          end

          def perform_rollback_config(ssh)
            output = ssh.exec! <<~'EOH'
              set -e

              echo "🔁 Backing up SSH config…"
              sudo test -f /etc/ssh/sshd_config.bak || sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak && echo "   - sshd_config backed up"

              echo "✍🏻 Restoring SSH config…"
              grep -q '^PermitRootLogin yes' /etc/ssh/sshd_config \
                || sudo sed -i 's/^#*PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config && echo "   - PermitRootLogin yes"
              grep -q '^PasswordAuthentication yes' /etc/ssh/sshd_config \
                || sudo sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config && echo "   - PasswordAuthentication yes"
              sudo systemctl restart sshd && echo "   - sshd restarted"
            EOH
            say output
            say "✅ SSH config restored, closing deploy session", :green
          end

          def perform_rollback_cleanup(ssh)
            output = ssh.exec! <<~'EOH'
              set -e

              echo "✍🏻 Removing sudoers file…"
              if [ -f /etc/sudoers.d/deploy ]; then
                sudo rm -f /etc/sudoers.d/deploy && echo "   - /etc/sudoers.d/deploy removed"
              else
                echo "   - no sudoers file to remove"
              fi

              echo "✍🏻 Killing remaining processes for deploy…"
              if id deploy &>/dev/null; then
                sudo pkill -u deploy && echo "   - processes killed" || echo "   - no processes found"
              else
                echo "   - user 'deploy' does not exist, skipping"
              fi

              echo "✍🏻 Deleting deploy user…"
              if id deploy &>/dev/null; then
                if command -v deluser &>/dev/null; then
                  sudo deluser --remove-home deploy && echo "   - deploy user removed"
                else
                  sudo userdel -r deploy && echo "   - deploy user removed"
                fi
              else
                echo "   - deploy user does not exist"
              fi
            EOH
            say output
          end
        end
      end
    end
  end
end
