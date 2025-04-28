require "thor"
require_relative "env_loader"
require_relative "commands/init"
require_relative "commands/switch_env"
require_relative "commands/provision"
require_relative "commands/setup_user"
require_relative "commands/setup_firewall"
require_relative "commands/setup_unattended"
require_relative "commands/bootstrap"
require_relative "commands/setup_docker_prereqs"
require_relative "commands/install_docker_engine"
require_relative "commands/postinstall_docker"
require_relative "commands/bootstrap_docker"
require_relative "commands/setup_postgres_docker"

module Kitsune
  module Kit
    class CLI < Thor
      def self.dispatch(m, args, options, config)
        unless ["init", "switch_env"].include?(args.first)
          Kitsune::Kit::EnvLoader.load!
        end

        super
      end

      desc "init", "Initialize Kitsune Kit project structure"
      subcommand "init", Kitsune::Kit::Commands::Init

      desc "switch_env SUBCOMMAND", "Switch the active Kitsune environment"
      subcommand "switch_env", Kitsune::Kit::Commands::SwitchEnv

      desc "provision SUBCOMMAND", "Provisioning tasks"
      subcommand "provision", Kitsune::Kit::Commands::Provision

      desc "setup_user SUBCOMMAND", "Create or rollback deploy user on remote server"
      subcommand "setup_user", Kitsune::Kit::Commands::SetupUser

      desc "setup_firewall SUBCOMMAND", "Configure or rollback UFW firewall rules"
      subcommand "setup_firewall", Kitsune::Kit::Commands::SetupFirewall

      desc "setup_unattended SUBCOMMAND", "Configure or rollback unattended-upgrades"
      subcommand "setup_unattended", Kitsune::Kit::Commands::SetupUnattended

      desc "bootstrap SUBCOMMAND", "Run full server setup or rollback"
      subcommand "bootstrap", Kitsune::Kit::Commands::Bootstrap

      desc "setup_docker_prereqs SUBCOMMAND", "Install or rollback docker prerequisites"
      subcommand "setup_docker_prereqs", Kitsune::Kit::Commands::SetupDockerPrereqs

      desc "install_docker_engine SUBCOMMAND", "Install or rollback Docker Engine"
      subcommand "install_docker_engine", Kitsune::Kit::Commands::InstallDockerEngine

      desc "postinstall_docker SUBCOMMAND", "Apply or rollback Docker post-installation tasks"
      subcommand "postinstall_docker", Kitsune::Kit::Commands::PostinstallDocker

      desc "bootstrap_docker SUBCOMMAND", "Run full docker setup or rollback"
      subcommand "bootstrap_docker", Kitsune::Kit::Commands::BootstrapDocker

      desc "setup_postgres_docker SUBCOMMAND", "Setup PostgreSQL via Docker Compose on remote server"
      subcommand "setup_postgres_docker", Kitsune::Kit::Commands::SetupPostgresDocker
    end
  end
end
