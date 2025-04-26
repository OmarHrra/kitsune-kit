require "thor"
require "dotenv/load"
require_relative "commands/setup_user"
require_relative "commands/provision"
require_relative "commands/setup_firewall"
require_relative "commands/setup_unattended"
require_relative "commands/bootstrap"
require_relative "commands/setup_docker_prereqs"

module Kitsune
  module Kit
    class CLI < Thor
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
    end
  end
end
