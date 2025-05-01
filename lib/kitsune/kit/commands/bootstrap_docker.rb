require "thor"
require "open3"
require_relative "../defaults"
require_relative "../options_builder"

module Kitsune
  module Kit
    module Commands
      class BootstrapDocker < Thor
        namespace "bootstrap_docker"

        class_option :server_ip,    aliases: "-s", required: true, desc: "Server IP address or hostname"
        class_option :ssh_port,     aliases: "-p", desc: "SSH port for server"
        class_option :ssh_key_path, aliases: "-k", desc: "SSH private key path"
        class_option :rollback,     type: :boolean, default: false, desc: "Rollback Docker setup steps"

        desc "execute", "Run full Docker setup or rollback sequence"
        def execute
          filled_options = Kitsune::Kit::OptionsBuilder.build(
            options,
            required: [:server_ip],
            defaults: Kitsune::Kit::Defaults.ssh
          )

          if filled_options[:rollback]
            say "🔄 Rolling back full Docker setup...", :yellow
            rollback_sequence(filled_options)
          else
            say "🐳 Running full Docker setup...", :green
            setup_sequence(filled_options)
          end

          say "🎉 Done!", :green
        end

        no_commands do
          def setup_sequence(filled_options)
            run_cli("setup_docker_prereqs create", filled_options)
            run_cli("install_docker_engine create", filled_options)
            run_cli("postinstall_docker create", filled_options)
          end

          def rollback_sequence(filled_options)
            run_cli("postinstall_docker rollback", filled_options)
            run_cli("install_docker_engine rollback", filled_options)
            run_cli("setup_docker_prereqs rollback", filled_options)
          end

          def run_cli(command, filled_options)
            say "\n▶️ Running: kitsune kit #{command} --server-ip #{filled_options[:server_ip]}", :blue

            subcommand, action = command.split(" ", 2)
            Kitsune::Kit::CLI.start([
              subcommand, action,
              "--server-ip", filled_options[:server_ip],
              "--ssh-port",  filled_options[:ssh_port],
              "--ssh-key-path", filled_options[:ssh_key_path]
            ])
          rescue SystemExit => e
            abort "❌ Command failed: #{command} (exit #{e.status})"
          end
        end
      end
    end
  end
end
