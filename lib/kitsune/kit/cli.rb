require "thor"
require_relative "ansi_color"
require_relative "env_loader"
require_relative "commands/init"
require_relative "commands/switch_env"
require_relative "commands/provision"
require_relative "commands/dns"
require_relative "commands/setup_user"
require_relative "commands/setup_firewall"
require_relative "commands/setup_unattended"
require_relative "commands/setup_swap"
require_relative "commands/setup_do_metrics"
require_relative "commands/bootstrap"
require_relative "commands/setup_docker_prereqs"
require_relative "commands/install_docker_engine"
require_relative "commands/postinstall_docker"
require_relative "commands/bootstrap_docker"
require_relative "commands/setup_postgres_docker"
require_relative "commands/setup_redis_docker"
require_relative "commands/ssh"

module Kitsune
  module Kit
    class CLI < Thor
      def self.dispatch(m, args, options, config)
        if args.include?("-v") || args.include?("--version")
          puts "Kitsune Kit v#{Kitsune::Kit::VERSION}"
          exit(0)
        end
      
        unless ["version", "init", "switch_env", "help", nil].include?(args.first)
          Kitsune::Kit::EnvLoader.load!
        end

        super
      end

      desc "version", "Show Kitsune Kit version"
      def version
        say "Kitsune Kit v#{Kitsune::Kit::VERSION}", :green
      end

      desc "init", "Initialize Kitsune Kit project structure"
      subcommand "init", Kitsune::Kit::Commands::Init

      desc "switch_env SUBCOMMAND", "Switch the active Kitsune environment"
      subcommand "switch_env", Kitsune::Kit::Commands::SwitchEnv

      desc "provision SUBCOMMAND", "Provisioning tasks"
      subcommand "provision", Kitsune::Kit::Commands::Provision

      desc "dns SUBCOMMAND", "Manage DNS"
      subcommand "dns", Kitsune::Kit::Commands::Dns

      desc "setup_user SUBCOMMAND", "Create or rollback deploy user on remote server"
      subcommand "setup_user", Kitsune::Kit::Commands::SetupUser

      desc "setup_firewall SUBCOMMAND", "Configure or rollback UFW firewall rules"
      subcommand "setup_firewall", Kitsune::Kit::Commands::SetupFirewall

      desc "setup_unattended SUBCOMMAND", "Configure or rollback unattended-upgrades"
      subcommand "setup_unattended", Kitsune::Kit::Commands::SetupUnattended

      desc "setup_swap SUBCOMMAND", "Configure or rollback swap memory"
      subcommand "setup_swap", Kitsune::Kit::Commands::SetupSwap

      desc "setup_do_metrics SUBCOMMAND", "Install or rollback DigitalOcean Metrics Agent"
      subcommand "setup_do_metrics", Kitsune::Kit::Commands::SetupDoMetrics

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

      desc "setup_redis_docker SUBCOMMAND", "Setup Redis via Docker Compose on remote server"
      subcommand "setup_redis_docker", Kitsune::Kit::Commands::SetupRedisDocker

      desc "ssh connect", "SSH into the server"
      subcommand "ssh", Kitsune::Kit::Commands::Ssh
    end
  end
end
