require "thor"
require "dotenv/load"
require_relative "commands/setup_user"
require_relative "commands/provision"
require_relative "commands/setup_firewall"

module Kitsune
  module Kit
    class CLI < Thor
      desc "provision SUBCOMMAND", "Provisioning tasks"
      subcommand "provision", Kitsune::Kit::Commands::Provision

      desc "setup_user SUBCOMMAND", "Create or rollback deploy user on remote server"
      subcommand "setup_user", Kitsune::Kit::Commands::SetupUser

      desc "setup_firewall SUBCOMMAND", "Configure or rollback UFW firewall rules"
      subcommand "setup_firewall", Kitsune::Kit::Commands::SetupFirewall
    end
  end
end
