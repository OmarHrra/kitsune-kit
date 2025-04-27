require "thor"
require "open3"

module Kitsune
  module Kit
    module Commands
      class BootstrapDocker < Thor
        namespace "bootstrap_docker"

        class_option :server_ip,    aliases: "-s", required: true, desc: "Server IP address or hostname"
        class_option :ssh_port,     aliases: "-p", default: ENV['SSH_PORT'] || '22', desc: "SSH port for server"
        class_option :ssh_key_path, aliases: "-k", default: ENV['SSH_KEY_PATH'] || '~/.ssh/id_rsa', desc: "SSH private key path"
        class_option :rollback,     type: :boolean, default: false, desc: "Rollback Docker setup steps"

        desc "execute", "Run full Docker setup or rollback sequence"
        def execute
          if options[:rollback]
            say "🔄 Rolling back full Docker setup...", :yellow
            rollback_sequence
          else
            say "🐳 Running full Docker setup...", :green
            setup_sequence
          end

          say "🎉 Done!", :green
        end

        no_commands do
          def setup_sequence
            run_cli("setup_docker_prereqs create")
            run_cli("install_docker_engine create")
            run_cli("postinstall_docker create")
          end

          def rollback_sequence
            run_cli("postinstall_docker rollback")
            run_cli("install_docker_engine rollback")
            run_cli("setup_docker_prereqs rollback")
          end

          def run_cli(command)
            say "▶️ Running: kitsune kit #{command} --server-ip #{options[:server_ip]}", :blue
          
            subcommand, action = command.split(" ", 2)
            Kitsune::Kit::CLI.start([
              subcommand, action,
              "--server-ip",    options[:server_ip],
              "--ssh-port",     options[:ssh_port],
              "--ssh-key-path", options[:ssh_key_path]
            ])
          rescue SystemExit => e
            abort "❌ Command failed: #{command} (exit #{e.status})"
          end
        end
      end
    end
  end
end
