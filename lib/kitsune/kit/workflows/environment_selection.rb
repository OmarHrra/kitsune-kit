# frozen_string_literal: true

require "fileutils"
require "pathname"
require "tempfile"
require_relative "../errors"

module Kitsune
  module Kit
    module Workflows
      class EnvironmentSelection
        NAME = /\A[a-z0-9][a-z0-9_-]*\z/

        def initialize(root: Dir.pwd)
          @root = Pathname(root).expand_path
        end

        def list
          environments_directory.glob("*.yml").map { |path| path.basename(".yml").to_s }.sort
        end

        def current(env: ENV)
          env["KITSUNE_ENV"] || selected_from_file || "development"
        end

        def use(name)
          validate_name!(name)
          unless list.include?(name)
            raise Errors::ConfigurationError.new(
              "environment does not exist: #{name}",
              hint: "Create .kitsune/environments/#{name}.yml, then retry."
            )
          end

          FileUtils.mkdir_p(base_directory, mode: 0o700)
          Tempfile.create(["environment", ".tmp"], base_directory.to_s, mode: 0o600) do |file|
            file.write("#{name}\n")
            file.flush
            file.fsync
            File.rename(file.path, selection_path)
          end
          File.chmod(0o600, selection_path)
          name
        end

        private

        attr_reader :root

        def base_directory = root.join(".kitsune")
        def environments_directory = base_directory.join("environments")
        def selection_path = base_directory.join("environment")

        def selected_from_file
          return unless selection_path.file?

          value = selection_path.read.strip
          validate_name!(value)
          value
        end

        def validate_name!(name)
          return if name.to_s.match?(NAME)

          raise Errors::ConfigurationError, "environment name has an invalid format"
        end
      end
    end
  end
end
