require "thor"
require "stringio"
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
            run_cli("setup_swap create", droplet_ip, filled_options)
            run_cli("setup_do_metrics create", droplet_ip, filled_options)
            run_cli("dns link", droplet_ip, filled_options.merge(domains: ENV["DOMAIN_NAMES"]))
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

            run_cli("setup_do_metrics rollback", droplet_ip, filled_options)

            if ssh_accessible?(droplet_ip, filled_options)
              run_cli("setup_unattended rollback", droplet_ip, filled_options)
              run_cli("setup_firewall rollback", droplet_ip, filled_options)
            else
              say "⏭️  Skipping unattended-upgrades and firewall rollback (no deploy user)", :yellow
            end

            run_cli("setup_swap rollback", droplet_ip, filled_options)
            run_cli("setup_user rollback", droplet_ip, filled_options)

            unless filled_options[:keep_server]
              run_cli("dns rollback", droplet_ip, filled_options.merge(domains: ENV["DOMAIN_NAMES"]))
              say "▶️ Running: kitsune kit provision rollback", :blue
              Kitsune::Kit::CLI.start(%w[provision rollback])
            else
              say "⏭️  Skipping droplet deletion (--keep-server enabled), DNS rollback won't be executed", :yellow
            end
          end

          def fetch_droplet_ip
            out = StringIO.new
            $stdout = out
            begin
              Kitsune::Kit::CLI.start(["provision", "create"])
            ensure
              $stdout = STDOUT
            end
          
            ip = out.string[/(\d{1,3}\.){3}\d{1,3}/]
            abort "❌ Could not detect droplet IP!" if ip.nil? || ip.empty?
            ip
          end

          def run_cli(command, droplet_ip, filled_options)
            say "\n▶️ Running: kitsune kit #{command} --server-ip #{droplet_ip}", :blue
            subcommand, action = command.split(" ", 2)

            args = [subcommand, action, "--server-ip", droplet_ip]

            if subcommand != "dns"
              args += ["--ssh-port", filled_options[:ssh_port], "--ssh-key-path", filled_options[:ssh_key_path]]
            end

            if subcommand == "dns" && ENV["DOMAIN_NAMES"]
              args += ["--domains", ENV["DOMAIN_NAMES"]]
            end

            Kitsune::Kit::CLI.start(args)
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
