require "thor"
require "net/ssh"
require_relative "../defaults"
require_relative "../options_builder"

module Kitsune
  module Kit
    module Commands
      class SetupFirewall < Thor
        namespace "setup_firewall"

        class_option :server_ip,    aliases: "-s", required: true, desc: "Server IP address or hostname"
        class_option :ssh_port,     aliases: "-p", desc: "SSH port"
        class_option :ssh_key_path, aliases: "-k", desc: "Path to your private SSH key"

        desc "create", "Setup UFW firewall rules on the remote server"
        def create
          filled_options = Kitsune::Kit::OptionsBuilder.build(
            options,
            required: [:server_ip],
            defaults: Kitsune::Kit::Defaults.ssh
          )

          with_ssh_connection(filled_options) do |ssh|
            perform_setup(ssh, filled_options)
          end
        end

        desc "rollback", "Remove UFW firewall rules and disable UFW on the remote server"
        def rollback
          filled_options = Kitsune::Kit::OptionsBuilder.build(
            options,
            required: [:server_ip],
            defaults: Kitsune::Kit::Defaults.ssh
          )

          with_ssh_connection(filled_options) do |ssh|
            perform_rollback(ssh, filled_options)
          end
        end

        no_commands do
          def with_ssh_connection(filled_options)
            server = filled_options[:server_ip]
            port   = filled_options[:ssh_port]
            key    = File.expand_path(filled_options[:ssh_key_path])

            say "🔑 Connecting as deploy@#{server}:#{port}", :green
            Net::SSH.start(server, "deploy", port: port, keys: [key], non_interactive: true, timeout: 5) do |ssh|
              yield ssh
            end
          end

          def perform_setup(ssh, filled_options)
            ssh_port = filled_options[:ssh_port]

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
              add_rule "#{ssh_port}/tcp"
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

          def perform_rollback(ssh, filled_options)
            ssh_port = filled_options[:ssh_port]

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
              delete_rule "#{ssh_port}/tcp"
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
