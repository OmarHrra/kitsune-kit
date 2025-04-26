require "thor"
require "net/ssh"

module Kitsune
  module Kit
    module Commands
      class PostinstallDocker < Thor
        namespace "postinstall_docker"

        class_option :server_ip,    aliases: "-s", required: true, desc: "Server IP address or hostname"
        class_option :ssh_port,     aliases: "-p", default: ENV['SSH_PORT'] || '22', desc: "SSH port"
        class_option :ssh_key_path, aliases: "-k", default: ENV['SSH_KEY_PATH'] || '~/.ssh/id_rsa', desc: "Path to your private SSH key"

        desc "create", "Apply Docker post-install configuration (start service, add groups, create network)"
        def create
          with_ssh_connection do |ssh|
            perform_setup(ssh)
          end
        end

        desc "rollback", "Undo Docker post-install configuration"
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

              sudo mkdir -p /usr/local/backups
              sudo chown deploy:deploy /usr/local/backups

              BACKUP_DIR="/usr/local/backups"
              SCRIPT_ID="postinstall_docker"
              BEFORE_FILE="${BACKUP_DIR}/${SCRIPT_ID}.before"
              AFTER_FILE="${BACKUP_DIR}/${SCRIPT_ID}.after"

              echo "✍🏻 Performing post-install Docker tasks"

              if [ ! -f "$AFTER_FILE" ]; then
                # Record state
                systemctl is-enabled docker &>/dev/null && echo "docker.service enabled" >> "$BEFORE_FILE" || echo "docker.service disabled" >> "$BEFORE_FILE"
                groups deploy | grep -q docker && echo "deploy in docker group" >> "$BEFORE_FILE" || echo "deploy not in docker group" >> "$BEFORE_FILE"
                sudo docker network inspect private &>/dev/null && echo "network private exists" >> "$BEFORE_FILE" || echo "network private absent" >> "$BEFORE_FILE"

                # Start and enable Docker
                sudo systemctl start docker
                sudo systemctl enable docker
                echo "🚀 Docker service started and enabled"
                echo "docker.service enabled" >> "$AFTER_FILE"

                # Add deploy to docker group
                sudo usermod -aG docker deploy
                echo "👥 Added 'deploy' to docker group"
                echo "added docker group" >> "$AFTER_FILE"

                # Create private network if missing
                if ! sudo docker network inspect private &>/dev/null; then
                  sudo docker network create -d bridge private
                  echo "🌐 Created Docker network 'private'"
                  echo "created network private" >> "$AFTER_FILE"
                fi

                echo "✅ Post-install Docker tasks complete"
              else
                echo "🔄 Post-install tasks already applied, skipping setup"
              fi
            EOH
            say output
            say "✅ Post-install Docker setup completed", :green
          end

          def perform_rollback(ssh)
            output = ssh.exec! <<~EOH
              set -e

              sudo mkdir -p /usr/local/backups
              sudo chown deploy:deploy /usr/local/backups

              BACKUP_DIR="/usr/local/backups"
              SCRIPT_ID="postinstall_docker"
              BEFORE_FILE="${BACKUP_DIR}/${SCRIPT_ID}.before"
              AFTER_FILE="${BACKUP_DIR}/${SCRIPT_ID}.after"

              echo "🔄 Rolling back post-install Docker tasks..."

              if [ -f "$AFTER_FILE" ]; then
                if grep -Fxq "docker.service enabled" "$AFTER_FILE"; then
                  sudo systemctl disable docker
                  echo "   - Docker service disabled"
                fi
                if grep -Fxq "added docker group" "$AFTER_FILE"; then
                  sudo gpasswd -d deploy docker || true
                  echo "   - Removed 'deploy' from docker group"
                fi
                if grep -Fxq "created network private" "$AFTER_FILE"; then
                  sudo docker network rm private || true
                  echo "   - Removed Docker network 'private'"
                fi
                sudo rm -f "$BEFORE_FILE" "$AFTER_FILE"
              else
                echo "   - no marker for $SCRIPT_ID, skipping rollback"
              fi

              echo "✅ Rollback complete"
            EOH
            say output
            say "✅ Post-install Docker rollback completed", :green
          end
        end
      end
    end
  end
end
