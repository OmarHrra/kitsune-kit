require "thor"
require "dotenv/load"
require_relative "commands/provision"

module Kitsune
  module Kit
    class CLI < Thor
      desc "provision SUBCOMMAND", "Provisioning tasks"
      subcommand "provision", Kitsune::Kit::Commands::Provision
    end
  end
end
