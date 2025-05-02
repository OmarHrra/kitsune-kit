require "thor"
require "net/ssh"
require_relative "../defaults"
require_relative "../options_builder"

module Kitsune
  module Kit
    module Commands
      class SetupDoMetrics < Thor
        namespace "setup_do_metrics"

        class_option :server_ip, aliases: "-s", required: true, desc: "Server IP address"
        class_option :ssh_port, aliases: "-p", desc: "SSH port"
        class_option :ssh_key_path, aliases: "-k", desc: "SSH private key path"

        desc "create", "Install and enable the DigitalOcean Metrics Agent"
        def create
          unless Kitsune::Kit::Defaults.metrics[:enable_do_metrics]
            say "⚠️ DigitalOcean Metrics Agent setup is disabled via ENABLE_DO_METRICS=false", :yellow
            return
          end

          filled_options = Kitsune::Kit::OptionsBuilder.build(
            options,
            required: [:server_ip],
            defaults: Kitsune::Kit::Defaults.ssh
          )

          with_ssh(filled_options) do |ssh|
            install_agent(ssh)
          end
        end

        desc "rollback", "Uninstall the DigitalOcean Metrics Agent"
        def rollback
          filled_options = Kitsune::Kit::OptionsBuilder.build(
            options,
            required: [:server_ip],
            defaults: Kitsune::Kit::Defaults.ssh
          )

          with_ssh(filled_options) do |ssh|
            uninstall_agent(ssh)
          end
        end

        no_commands do
          def with_ssh(filled_options)
            Net::SSH.start(
              filled_options[:server_ip],
              "deploy",
              port: filled_options[:ssh_port],
              keys: [File.expand_path(filled_options[:ssh_key_path])],
              non_interactive: true,
              timeout: 5
            ) do |ssh|
              yield ssh
            end
          end

          def install_agent(ssh)
            marker = "/usr/local/backups/setup_do_metrics.after"

            script = <<~BASH
              set -e
              sudo mkdir -p /usr/local/backups

              if [ -f "#{marker}" ]; then
                echo "🔁 Metrics Agent already installed, skipping."
                exit 0
              fi

              echo "✍🏻 Installing DigitalOcean Metrics Agent..."
              curl -sSL https://repos.insights.digitalocean.com/install.sh | sudo bash

              sudo touch "#{marker}"
              echo "✅ Metrics Agent installed"

              ps aux | grep do-agent | grep -v grep || echo "⚠️ do-agent process not found"
            BASH

            say ssh.exec!(script)
          end

          def uninstall_agent(ssh)
            marker = "/usr/local/backups/setup_do_metrics.after"

            script = <<~BASH
              set -e

              if [ ! -f "#{marker}" ]; then
                echo "💡 No marker for metrics agent found. Skipping rollback."
                exit 0
              fi

              echo "🧹 Uninstalling DigitalOcean Metrics Agent..."

              if dpkg -l | grep -q do-agent; then
                echo "📦 Removing do-agent package..."
                sudo apt-get remove --purge -y do-agent
              else
                echo "💡 do-agent is not installed, skipping package removal."
              fi

              if systemctl list-unit-files | grep -q do-agent.service; then
                echo "✍🏻 Stopping do-agent service..."
                sudo systemctl stop do-agent || true
                sudo systemctl disable do-agent || true
              else
                echo "💡 do-agent.service not found in systemd, skipping stop/disable"
              fi

              sudo rm -f "#{marker}"
              echo "✅ Metrics Agent removed"
            BASH

            say ssh.exec!(script)
          end
        end
      end
    end
  end
end
