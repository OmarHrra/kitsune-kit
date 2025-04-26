require "thor"
require "net/ssh"

module Kitsune
  module Kit
    module Commands
      class SetupUnattended < Thor
        namespace "setup_unattended"

        class_option :server_ip,    aliases: "-s", required: true, desc: "Server IP address or hostname"
        class_option :ssh_port,     aliases: "-p", default: ENV['SSH_PORT'] || '22', desc: "SSH port"
        class_option :ssh_key_path, aliases: "-k", default: ENV['SSH_KEY_PATH'] || '~/.ssh/id_rsa', desc: "Path to your private SSH key"

        desc "create", "Configure unattended-upgrades on the remote server"
        def create
          with_ssh_connection do |ssh|
            perform_setup(ssh)
          end
        end

        desc "rollback", "Revert unattended-upgrades configuration on the remote server"
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

              RESOURCE="/etc/apt/apt.conf.d/20auto-upgrades"
              BACKUP_DIR="/usr/local/backups"
              SCRIPT_ID="setup_unattended"
              BACKUP_FILE="${BACKUP_DIR}/${SCRIPT_ID}.before"
              MARKER_FILE="${BACKUP_DIR}/${SCRIPT_ID}.after"

              echo "✍🏻 Installing required packages…"
              if ! dpkg -l | grep -q "^ii\\s*unattended-upgrades"; then
                sudo apt-get update -y
                sudo apt-get install -y unattended-upgrades apt-listchanges && echo "   - packages installed"
              else
                echo "   - unattended-upgrades already installed"
              fi

              if [ ! -f "$MARKER_FILE" ]; then
                echo "✍🏻 Backing up existing config…"
                sudo cp "$RESOURCE" "$BACKUP_FILE" && echo "   - backup saved to $BACKUP_FILE"
                sudo touch "$MARKER_FILE" && echo "   - marker created at $MARKER_FILE"
              else
                echo "   - backup & marker already exist"
              fi

              echo "✍🏻 Applying new auto-upgrades config…"
              sudo tee "$RESOURCE" > /dev/null <<UPGR
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
UPGR
              echo "   - config applied"

              echo "✍🏻 Enabling & restarting unattended-upgrades…"
              sudo systemctl --quiet enable unattended-upgrades.service >/dev/null 2>&1 && echo "   - service enabled"
              sudo systemctl --quiet restart unattended-upgrades.service && echo "   - service restarted"
            EOH
            say output
            say "✅ Unattended-upgrades setup completed", :green
          end

          def perform_rollback(ssh)
            output = ssh.exec! <<~EOH
              set -e
              
              sudo mkdir -p /usr/local/backups
              sudo chown deploy:deploy /usr/local/backups

              RESOURCE="/etc/apt/apt.conf.d/20auto-upgrades"
              BACKUP_DIR="/usr/local/backups"
              SCRIPT_ID="setup_unattended"
              BACKUP_FILE="${BACKUP_DIR}/${SCRIPT_ID}.before"
              MARKER_FILE="${BACKUP_DIR}/${SCRIPT_ID}.after"

              if [ -f "$MARKER_FILE" ]; then
                echo "🔁 Restoring original auto-upgrades config…"
                sudo mv "$BACKUP_FILE" "$RESOURCE" && echo "   - config restored from $BACKUP_FILE"
                sudo rm -f "$MARKER_FILE" && echo "   - marker $MARKER_FILE removed"
              else
                echo "   - no marker for $SCRIPT_ID, skipping restore"
              fi

              echo "✍🏻 Stopping & disabling unattended-upgrades…"
              sudo systemctl --quiet stop unattended-upgrades.service apt-daily.timer apt-daily-upgrade.timer && echo "   - services stopped"
              sudo systemctl --quiet disable unattended-upgrades.service && echo "   - service disabled"
            EOH
            say output
            say "✅ Unattended-upgrades rollback completed", :green
          end
        end
      end
    end
  end
end
