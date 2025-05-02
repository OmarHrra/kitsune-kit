require "thor"
require "net/ssh"
require_relative "../defaults"
require_relative "../options_builder"

module Kitsune
  module Kit
    module Commands
      class SetupSwap < Thor
        namespace "setup_swap"

        class_option :server_ip, aliases: "-s", required: true, desc: "Server IP address"
        class_option :ssh_port, aliases: "-p", desc: "SSH port"
        class_option :ssh_key_path, aliases: "-k", desc: "SSH private key path"
        class_option :size_gb, type: :numeric, desc: "Swap size in GB"
        class_option :swappiness, type: :numeric, desc: "vm.swappiness value (0-100)"

        desc "create", "Create and activate a swap file on the remote server"
        def create
          if Kitsune::Kit::Defaults.system[:disable_swap]
            say "⚠️ Swap setup is disabled via DISABLE_SWAP=true", :yellow
            return
          end

          filled_options = Kitsune::Kit::OptionsBuilder.build(
            options,
            required: [:server_ip],
            defaults: Kitsune::Kit::Defaults.system.merge(Kitsune::Kit::Defaults.ssh)
          )

          with_ssh_connection(filled_options) do |ssh|
            perform_setup(ssh, filled_options)
          end
        end

        desc "rollback", "Disable and remove swap file from remote server"
        def rollback
          filled_options = Kitsune::Kit::OptionsBuilder.build(
            options,
            required: [:server_ip],
            defaults: Kitsune::Kit::Defaults.system.merge(Kitsune::Kit::Defaults.ssh)
          )

          with_ssh_connection(filled_options) do |ssh|
            perform_rollback(ssh)
          end
        end

        no_commands do
          def with_ssh_connection(filled)
            server = filled[:server_ip]
            port   = filled[:ssh_port]
            key    = File.expand_path(filled[:ssh_key_path])

            say "🔑 Connecting as deploy@#{server}:#{port}", :green
            Net::SSH.start(server, "deploy", port: port, keys: [key], non_interactive: true, timeout: 5) do |ssh|
              yield ssh
            end
          end

          def perform_setup(ssh, filled_options)
            size_gb = filled_options[:swap_size_gb].to_i
            swappiness = filled_options[:swap_swappiness].to_i

            abort "❌ Invalid swap size" if size_gb <= 0

            script = <<~EOH
              set -e

              BACKUP_DIR="/usr/local/backups"
              MARKER_FILE="${BACKUP_DIR}/setup_swap.after"
              SWAPPINESS_BEFORE_FILE="${BACKUP_DIR}/setup_swap.swappiness.before"

              if [ -f "$MARKER_FILE" ]; then
                echo "🔁 Swap already set up, skipping."
                exit 0
              fi

              SWAPFILE="/swapfile"
              SIZE_GB=#{size_gb}
              SIZE_BYTES=$((SIZE_GB * 1024 * 1024 * 1024))

              echo "📝 Creating ${SIZE_GB}GB swap file..."
              sudo fallocate -l ${SIZE_BYTES} ${SWAPFILE}
              sudo chmod 600 ${SWAPFILE}
              sudo mkswap ${SWAPFILE}
              sudo swapon ${SWAPFILE}
              echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

              # Backup swappiness if not already backed up
              if [ ! -f "$SWAPPINESS_BEFORE_FILE" ]; then
                CURRENT=$(cat /proc/sys/vm/swappiness)
                echo "$CURRENT" | sudo tee "$SWAPPINESS_BEFORE_FILE"
                echo "✍🏻 Backed up vm.swappiness: $CURRENT"
              fi

              echo "🛠️ Setting vm.swappiness=#{swappiness}"
              sudo sysctl vm.swappiness=#{swappiness}
              echo "vm.swappiness=#{swappiness}" | sudo tee -a /etc/sysctl.conf

              sudo mkdir -p "$BACKUP_DIR"
              sudo touch "$MARKER_FILE"

              echo "✅ Swap file created and swappiness set"
              free -h
            EOH

            say ssh.exec!(script)
          end

          def perform_rollback(ssh)
            script = <<~EOH
              set -e

              BACKUP_DIR="/usr/local/backups"
              MARKER_FILE="${BACKUP_DIR}/setup_swap.after"
              SWAPPINESS_BEFORE_FILE="${BACKUP_DIR}/setup_swap.swappiness.before"

              if [ ! -f "$MARKER_FILE" ]; then
                echo "💡 No swap marker found, skipping rollback."
                exit 0
              fi

              echo "🧹 Removing swap..."
              sudo swapoff /swapfile || true
              sudo rm -f /swapfile
              sudo sed -i '/\\/swapfile none swap sw 0 0/d' /etc/fstab
              sudo rm -f "$MARKER_FILE"

              if [ -f "$SWAPPINESS_BEFORE_FILE" ]; then
                ORIGINAL=$(cat "$SWAPPINESS_BEFORE_FILE")
                echo "🔁 Restoring vm.swappiness: $ORIGINAL"
                sudo sysctl vm.swappiness=$ORIGINAL
                sudo sed -i '/vm.swappiness=/d' /etc/sysctl.conf
                echo "vm.swappiness=$ORIGINAL" | sudo tee -a /etc/sysctl.conf
                sudo rm -f "$SWAPPINESS_BEFORE_FILE"
              else
                echo "💡 No swappiness backup found, skipping restore."
              fi

              echo "✅ Swap rollback completed"
              free -h
            EOH

            say ssh.exec!(script)
          end
        end
      end
    end
  end
end
