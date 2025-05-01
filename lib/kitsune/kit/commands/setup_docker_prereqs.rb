require "thor"
require "net/ssh"
require_relative "../options_builder"
require_relative "../defaults"

module Kitsune
  module Kit
    module Commands
      class SetupDockerPrereqs < Thor
        namespace "setup_docker_prereqs"

        class_option :server_ip,    aliases: "-s", required: true, desc: "Server IP address or hostname"
        class_option :ssh_port,     aliases: "-p", desc: "SSH port"
        class_option :ssh_key_path, aliases: "-k", desc: "Path to your private SSH key"

        desc "create", "Install Docker prerequisites on the remote server"
        def create
          filled_options = Kitsune::Kit::OptionsBuilder.build(
            options,
            required: [:server_ip],
            defaults: Kitsune::Kit::Defaults.ssh
          )

          with_ssh_connection(filled_options) do |ssh|
            perform_setup(ssh)
          end
        end

        desc "rollback", "Remove installed Docker prerequisites from the remote server"
        def rollback
          filled_options = Kitsune::Kit::OptionsBuilder.build(
            options,
            required: [:server_ip],
            defaults: Kitsune::Kit::Defaults.ssh
          )

          with_ssh_connection(filled_options) do |ssh|
            perform_rollback(ssh)
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

          def perform_setup(ssh)
            output = ssh.exec! <<~EOH
              set -e

              sudo mkdir -p /usr/local/backups
              sudo chown deploy:deploy /usr/local/backups

              BACKUP_DIR="/usr/local/backups"
              SCRIPT_ID="setup_docker_prereqs"
              BEFORE_FILE="${BACKUP_DIR}/${SCRIPT_ID}.before"
              AFTER_FILE="${BACKUP_DIR}/${SCRIPT_ID}.after"

              TARGET_PKGS=(
                apt-transport-https
                ca-certificates
                curl
                gnupg
                lsb-release
                software-properties-common
              )

              echo "✍🏻 TARGET_PKGS=(\${TARGET_PKGS[*]})"

              if [ ! -f "$AFTER_FILE" ]; then
                for pkg in "\${TARGET_PKGS[@]}"; do
                  if dpkg -l "\$pkg" &>/dev/null; then
                    echo "\$pkg" >> "$BEFORE_FILE"
                  fi
                done

                echo "✍🏻 Installing prerequisites..."
                sudo apt-get update -y
                sudo apt-get install -y "\${TARGET_PKGS[@]}"
                sudo touch "$AFTER_FILE" && echo "   - marker created at $AFTER_FILE"
              else
                echo "🔁 Already set up, ensuring latest"
                sudo apt-get update -y
                sudo apt-get install -y "\${TARGET_PKGS[@]}"
                echo "✅ Prerequisites are current"
              fi
            EOH
            say output
            say "✅ Docker prerequisites setup completed", :green
          end

          def perform_rollback(ssh)
            output = ssh.exec! <<~EOH
              set -e

              sudo mkdir -p /usr/local/backups
              sudo chown deploy:deploy /usr/local/backups

              BACKUP_DIR="/usr/local/backups"
              SCRIPT_ID="setup_docker_prereqs"
              BEFORE_FILE="${BACKUP_DIR}/${SCRIPT_ID}.before"
              AFTER_FILE="${BACKUP_DIR}/${SCRIPT_ID}.after"

              TARGET_PKGS=(
                apt-transport-https
                ca-certificates
                curl
                gnupg
                lsb-release
                software-properties-common
              )

              echo "✍🏻 TARGET_PKGS=(\${TARGET_PKGS[*]})"

              if [ -f "$AFTER_FILE" ]; then
                to_remove=()
                for pkg in "\${TARGET_PKGS[@]}"; do
                  if dpkg -l "\$pkg" &>/dev/null; then
                    if ! grep -Fxq "\$pkg" "$BEFORE_FILE"; then
                      to_remove+=("\$pkg")
                    fi
                  fi
                done

                if [ \${#to_remove[@]} -gt 0 ]; then
                  echo "🔁 Removing packages..."
                  sudo apt-get remove -y "\${to_remove[@]}" && echo "   - removed: \${to_remove[*]}"
                else
                  echo "   - no new packages to remove"
                fi

                sudo rm -f "$BEFORE_FILE" "$AFTER_FILE" && echo "   - backups removed"
              else
                echo "   - no marker for $SCRIPT_ID, skipping removal"
              fi
            EOH
            say output
            say "✅ Docker prerequisites rollback completed", :green
          end
        end
      end
    end
  end
end
