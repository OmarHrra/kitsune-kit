require "thor"
require "dotenv/load"
require_relative "commands/setup_user"
require_relative "commands/provision"
require_relative "commands/setup_firewall"
require_relative "commands/setup_unattended"

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
    end
  end
end
