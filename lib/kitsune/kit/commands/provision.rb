require "thor"
require "dotenv/load"
require_relative "../provisioner"

module Kitsune
  module Kit
    module Commands
      class Provision < Thor
        namespace "provision"

        class_option :droplet_name, type: :string, aliases: "-n",
                     default: ENV["DROPLET_NAME"] || "app-prod",
                     desc: "Droplet name"
        class_option :region, type: :string, aliases: "-r",
                     default: ENV["REGION"] || "sfo3",
                     desc: "Region"
        class_option :size, type: :string, aliases: "-s",
                     default: ENV["SIZE"] || "s-1vcpu-1gb",
                     desc: "Size"
        class_option :image, type: :string, aliases: "-i",
                     default: ENV["IMAGE"] || "ubuntu-22-04-x64",
                     desc: "Image"
        class_option :tag, type: :string, aliases: "-t",
                     default: ENV["TAG_NAME"] || "rails-prod",
                     desc: "Tag to filter/create"
        class_option :ssh_key_id, type: :string, aliases: "-k",
                     default: ENV["SSH_KEY_ID"],
                     desc: "SSH key ID"

        desc "create", "Create the Droplet if it doesn't exist"
        def create
          Provisioner.new(options).create_or_show
        end

        desc "rollback", "Remove the Droplet if it exists"
        def rollback
          Provisioner.new(options).rollback
        end
      end
    end
  end
end