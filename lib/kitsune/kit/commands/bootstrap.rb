require "thor"
require "open3"
require_relative "../defaults"
require_relative "../options_builder"
require_relative "../provisioner"

module Kitsune
  module Kit
    module Commands
      class Bootstrap < Thor
        namespace "bootstrap"

        class_option :rollback, type: :boolean, default: false, desc: "Rollback the setup"
        class_option :keep_server, type: :boolean, default: false, desc: "Keep server after rollback"
        class_option :ssh_port, type: :string, desc: "SSH port for server"
        class_option :ssh_key_path, type: :string, desc: "SSH private key path"

        desc "execute", "Run the full bootstrap process or rollback"
        def execute
          filled_options = Kitsune::Kit::OptionsBuilder.build(
            options,
            defaults: Kitsune::Kit::Defaults.ssh
          )

          if filled_options[:rollback]
            say "🔄 Rolling back server configurations...", :yellow
            rollback_sequence(filled_options)
          else
            say "🏗️ Setting up server from scratch...", :green
            setup_sequence(filled_options)
          end

          say "🎉 Done!", :green
        end

        no_commands do
          def setup_sequence(filled_options)
            droplet_ip = fetch_droplet_ip

            say "→ Droplet IP: #{droplet_ip}", :cyan

            run_cli("setup_user create", droplet_ip, filled_options)
            run_cli("setup_firewall create", droplet_ip, filled_options)
            run_cli("setup_unattended create", droplet_ip, filled_options)
          end

          def rollback_sequence(filled_options)
            provision_options = Kitsune::Kit::OptionsBuilder.build(
              {},
              defaults: Kitsune::Kit::Defaults::infra
            )

            provisioner = Kitsune::Kit::Provisioner.new(provision_options)

            if (droplet = provisioner.find_droplet).nil?
              say "💡 Nothing to rollback.", :green
              return
            end

            droplet_ip = provisioner.send(:public_ip, droplet)
            say "→ Using Droplet IP: #{droplet_ip}", :cyan

            if ssh_accessible?(droplet_ip, filled_options)
              run_cli("setup_unattended rollback", droplet_ip, filled_options)
              run_cli("setup_firewall rollback", droplet_ip, filled_options)
            else
              say "⏭️  Skipping unattended-upgrades and firewall rollback (no deploy user)", :yellow
            end

            run_cli("setup_user rollback", droplet_ip, filled_options)

            unless filled_options[:keep_server]
              say "▶️ Running: kitsune kit provision rollback", :blue
              Kitsune::Kit::CLI.start(%w[provision rollback])
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

          def run_cli(command, droplet_ip, filled_options)
            say "▶️ Running: kitsune kit #{command} --server-ip #{droplet_ip}", :blue
            subcommand, action = command.split(" ", 2)
            Kitsune::Kit::CLI.start([
              subcommand, action,
              "--server-ip", droplet_ip,
              "--ssh-port", filled_options[:ssh_port],
              "--ssh-key-path", filled_options[:ssh_key_path]
            ])
          rescue SystemExit => e
            abort "❌ Command failed: #{command} (exit #{e.status})"
          end

          def ssh_accessible?(droplet_ip, filled_options)
            system(
              "ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new " \
              "-p #{filled_options[:ssh_port]} " \
              "-i #{File.expand_path(filled_options[:ssh_key_path])} " \
              "deploy@#{droplet_ip} true",
              out: File::NULL,
              err: File::NULL
            )
          end
        end
      end
    end
  end
end
