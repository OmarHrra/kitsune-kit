require "thor"
require_relative "../defaults"
require_relative "../provisioner"
require_relative "../options_builder"

module Kitsune
  module Kit
    module Commands
      class Provision < Thor
        namespace "provision"

        class_option :droplet_name, type: :string, aliases: "-n", desc: "Droplet name"
        class_option :region, type: :string, aliases: "-r", desc: "Region"
        class_option :size, type: :string, aliases: "-s", desc: "Size"
        class_option :image, type: :string, aliases: "-i", desc: "Image"
        class_option :tag, type: :string, aliases: "-t", desc: "Tag to filter/create"
        class_option :ssh_key_id, type: :string, aliases: "-k", desc: "SSH key ID"

        desc "create", "Create the Droplet if it doesn't exist"
        def create
          filled_options = Kitsune::Kit::OptionsBuilder.build(
            options,
            required: [:ssh_key_id],
            defaults: Kitsune::Kit::Defaults.infra
          )

          Provisioner.new(filled_options).create_or_show
        end

        desc "rollback", "Remove the Droplet if it exists"
        def rollback
          filled_options = Kitsune::Kit::OptionsBuilder.build(
            options,
            required: [:ssh_key_id],
            defaults: Kitsune::Kit::Defaults.infra
          )

          Provisioner.new(filled_options).rollback
        end
      end
    end
  end
end