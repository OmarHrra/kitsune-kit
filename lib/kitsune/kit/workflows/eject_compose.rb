# frozen_string_literal: true

require "fileutils"
require "pathname"
require "tempfile"
require "yaml"
require_relative "../errors"
require_relative "../service_compose"

module Kitsune
  module Kit
    module Workflows
      class EjectCompose
        TYPES = %w[postgres redis].freeze

        def initialize(root:, config:, type:, config_path: nil)
          @root = Pathname(root).expand_path
          @config = config
          @type = type.to_s
          @config_path = config_path ? Pathname(config_path).expand_path(@root) : @root.join(".kitsune/config.yml")
        end

        def call(force: false)
          @backup_created = false
          validate_target!(force)
          content = ServiceCompose.new(config: config, type: type, service: service).generated_content
          FileUtils.mkdir_p(output_path.dirname, mode: 0o700)
          FileUtils.cp(config_path, backup_path)
          @backup_created = true
          write_atomic(output_path, content, 0o644)
          update_configuration
          { compose_file: output_path.to_s, config_file: config_path.to_s, backup_file: backup_path.to_s }
        rescue StandardError
          FileUtils.cp(backup_path, config_path) if @backup_created && backup_path.file?
          raise
        end

        private

        attr_reader :root, :config, :type, :config_path

        def service = config.services.public_send(type)
        def output_path = root.join(".kitsune/compose/#{type}.yml")
        def backup_path = Pathname("#{config_path}.backup")

        def validate_target!(force)
          raise Errors::ConfigurationError, "unknown service type: #{type}" unless TYPES.include?(type)
          raise Errors::ConfigurationError, "configuration file does not exist: #{config_path}" unless config_path.file?
          return if force || (!output_path.exist? && !backup_path.exist? && service.compose.mode == "generated")

          raise Errors::UnsafeOperationError.new(
            "refusing to replace an existing Compose customization or configuration backup",
            hint: "Review #{output_path} and #{backup_path}, then repeat with --force if replacement is intentional."
          )
        end

        def update_configuration
          document = YAML.safe_load(config_path.read, permitted_classes: [], permitted_symbols: [], aliases: false)
          service_config = document.fetch("services").fetch(type)
          service_config["compose"] = {
            "mode" => "custom",
            "file" => ".kitsune/compose/#{type}.yml",
            "allow_unsafe" => false
          }
          write_atomic(config_path, YAML.dump(document), 0o600)
        rescue KeyError, Psych::Exception => e
          raise Errors::ConfigurationError, "unable to update configuration for Compose ejection: #{e.message}"
        end

        def write_atomic(path, content, mode)
          Tempfile.create([path.basename.to_s, ".tmp"], path.dirname) do |file|
            file.write(content)
            file.flush
            file.fsync
            File.chmod(mode, file.path)
            File.rename(file.path, path)
          end
        end
      end
    end
  end
end
