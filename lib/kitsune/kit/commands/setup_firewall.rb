require "thor"
require "net/ssh"

module Kitsune
  module Kit
    module Commands
      class SetupFirewall < Thor
        namespace "setup_firewall"

        class_option :server_ip,    aliases: "-s", required: true, desc: "Server IP address or hostname"
        class_option :ssh_port,     aliases: "-p", default: ENV['SSH_PORT'] || '22', desc: "SSH port"
        class_option :ssh_key_path, aliases: "-k", default: ENV['SSH_KEY_PATH'] || '~/.ssh/id_rsa', desc: "Path to your private SSH key"

        desc "create", "Setup UFW firewall rules on the remote server"
        def create
          with_ssh_connection do |ssh|
            perform_setup(ssh)
          end
        end

        desc "rollback", "Remove UFW firewall rules and disable UFW on the remote server"
        def rollback
          with_ssh_connection do |ssh|
            perform_rollback(ssh)
          end
        end

        no_commands do
          def with_ssh_connection
            server = options[:server_ip]
            port   = options[:ssh_port]
            key    = File.expand_path(options[:ssh_key_path])

            say "🔑 Connecting as deploy@#{server}:#{port}", :green
            Net::SSH.start(server, "deploy", port: port, keys: [key], non_interactive: true, timeout: 5) do |ssh|
              yield ssh
            end
          end

          def perform_setup(ssh)
            output = ssh.exec! <<~EOH
              set -e

              echo "✍🏻 Updating repositories and ensuring UFW is installed…"
              if ! dpkg -l | grep -q ufw; then
                sudo apt-get update -y
                sudo apt-get install -y ufw && echo "   - ufw installed"
              else
                echo "   - ufw is already installed"
              fi

              echo "✍🏻 Configuring UFW rules…"
              add_rule() {
                local rule="$1"
                if ! sudo ufw status | grep -q "$rule"; then
                  sudo ufw allow "$rule" >/dev/null 2>&1 && echo "   - rule '$rule' added"
                else
                  echo "   - rule '$rule' already exists"
                fi
              }
              add_rule "#{options[:ssh_port]}/tcp"
              add_rule "80/tcp"
              add_rule "443/tcp"

              echo "✍🏻 Enabling UFW logging…"
              if ! sudo ufw status verbose | grep -q "Logging: on"; then
                sudo ufw logging on >/dev/null 2>&1 && echo "   - logging enabled"
              else
                echo "   - logging was already enabled"
              fi

              echo "✍🏻 Enabling UFW…"
              if sudo ufw status | grep -q "Status: inactive"; then
                sudo ufw --force enable >/dev/null 2>&1 && echo "   - UFW enabled"
              else
                echo "   - UFW is already enabled"
              fi
            EOH
            say output
            say "✅ Firewall setup completed", :green
          end

          def perform_rollback(ssh)
            output = ssh.exec! <<~EOH
              set -e

              echo "🔁 Removing UFW rules…"
              delete_rule() {
                local rule="$1"
                if sudo ufw status | grep -q "$rule"; then
                  sudo ufw delete allow "$rule" >/dev/null 2>&1 && echo "   - rule '$rule' removed"
                else
                  echo "   - rule '$rule' does not exist"
                fi
              }
              delete_rule "#{options[:ssh_port]}/tcp"
              delete_rule "80/tcp"
              delete_rule "443/tcp"

              echo "✍🏻 Disabling UFW if active…"
              if sudo ufw status | grep -q "Status: inactive"; then
                echo "   - UFW is already inactive"
              else
                sudo ufw --force disable >/dev/null 2>&1 && echo "   - UFW disabled"
              fi
            EOH
            say output
            say "✅ Firewall rollback completed", :green
          end
        end
      end
    end
  end
end
