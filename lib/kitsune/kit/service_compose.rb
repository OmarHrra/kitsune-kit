# frozen_string_literal: true

require "json"
require "digest"
require "pathname"
require "yaml"
require_relative "errors"

module Kitsune
  module Kit
    class ServiceCompose
      Document = Data.define(:filename, :content, :source)
      MAX_FILE_SIZE = 262_144
      MODES = %w[generated overlay custom].freeze
      SENSITIVE_KEY = /(?:password|passwd|secret|token|api[_-]?key)/i
      ENV_REFERENCE = /\A\$\{[A-Z][A-Z0-9_]*\}\z/

      attr_reader :mode, :security_findings

      def initialize(config:, type:, service:)
        @config = config
        @type = type.to_s
        @service = service
        @mode = service.compose.mode
        @security_findings = []
        validate!
      end

      def content = documents.first.content
      def generated_content = YAML.dump(generated_document)
      def env_content(password) = "#{@service.password_env}=#{JSON.generate(password)}\n"
      def filenames = documents.map(&:filename)

      def fingerprint
        Digest::SHA256.hexdigest([mode, *documents.flat_map { |item| [item.filename, item.content] }].join("\0"))
      end

      def documents
        @documents ||= case mode
                       when "generated"
                         [Document.new(filename: "compose.yml", content: generated_content, source: "generated")]
                       when "overlay"
                         [
                           Document.new(filename: "compose.yml", content: generated_content, source: "generated"),
                           Document.new(filename: "compose.override.yml", content: user_content,
                                        source: @service.compose.file)
                         ]
                       when "custom"
                         [Document.new(filename: "compose.yml", content: user_content, source: @service.compose.file)]
                       else
                         raise Errors::ConfigurationError, "unsupported Compose mode: #{mode}"
                       end
      end

      def display
        documents.map do |document|
          "# --- #{document.filename} (#{document.source}) ---\n#{document.content}"
        end.join("\n")
      end

      def metadata
        {
          mode: mode,
          files: documents.map { |document| { filename: document.filename, source: document.source } },
          allow_unsafe: @service.compose.allow_unsafe,
          security_findings: security_findings
        }
      end

      private

      def validate!
        raise Errors::ConfigurationError, "unsupported Compose mode: #{mode}" unless MODES.include?(mode)
        return if mode == "generated"

        document = user_document
        if mode == "custom"
          services = document["services"]
          unless services.is_a?(Hash) && services[@type].is_a?(Hash)
            raise Errors::ConfigurationError.new(
              "custom Compose file must define services.#{@type}",
              hint: "Run `kit service #{@type} compose eject` to create a valid starting point."
            )
          end
        end
        detect_inline_secrets(document)
        inspect_unsafe_options(document)
        return if security_findings.empty? || @service.compose.allow_unsafe

        raise Errors::UnsafeOperationError.new(
          "Compose customization contains unsafe options",
          hint: "Remove the options or set services.#{@type}.compose.allow_unsafe to true after review.",
          context: { service: @type, findings: security_findings }
        )
      end

      def user_content
        @user_content ||= Pathname(@service.compose.file).binread
      rescue SystemCallError => e
        raise Errors::ConfigurationError, "unable to read Compose customization: #{e.class}"
      end

      def user_document
        @user_document ||= begin
          if user_content.bytesize > MAX_FILE_SIZE
            raise Errors::ConfigurationError, "Compose customization exceeds 256 KiB"
          end

          parsed = YAML.safe_load(user_content, permitted_classes: [], permitted_symbols: [], aliases: false)
          unless parsed.is_a?(Hash)
            raise Errors::ConfigurationError, "Compose customization must contain a YAML mapping"
          end

          stringify_keys(parsed)
        rescue Psych::Exception => e
          raise Errors::ConfigurationError, "invalid Compose customization YAML: #{e.message}"
        end
      end

      def detect_inline_secrets(value, path = [])
        case value
        when Hash
          value.each do |key, child|
            if key.match?(SENSITIVE_KEY) && child.is_a?(String) && !child.match?(ENV_REFERENCE)
              raise Errors::ConfigurationError.new(
                "Compose customization contains an inline secret at #{(path + [key]).join('.')}",
                hint: "Reference an environment variable such as ${#{@service.password_env}} instead."
              )
            end
            detect_inline_secrets(child, path + [key])
          end
        when Array
          value.each_with_index { |child, index| detect_inline_secrets(child, path + [index.to_s]) }
        when String
          detect_inline_environment_secret(value, path)
        end
      end

      def detect_inline_environment_secret(value, path)
        key, content = value.split("=", 2)
        return unless content && key.match?(SENSITIVE_KEY) && !content.match?(ENV_REFERENCE)

        raise Errors::ConfigurationError.new(
          "Compose customization contains an inline secret at #{path.join('.')}",
          hint: "Use mapping syntax and reference ${#{@service.password_env}} instead."
        )
      end

      def inspect_unsafe_options(document)
        services = document["services"]
        return unless services.is_a?(Hash)

        services.each do |name, definition|
          next unless definition.is_a?(Hash)

          inspect_service(name, definition)
        end
      end

      def inspect_service(name, definition)
        prefix = "services.#{name}"
        finding("#{prefix}.privileged", "privileged containers") if definition["privileged"] == true
        inspect_namespaces(prefix, definition)
        inspect_capabilities(prefix, definition)
        inspect_ports(prefix, name, definition)
        finding("#{prefix}.devices", "host device access") if definition.key?("devices")
        finding("#{prefix}.build", "remote image builds") if definition.key?("build")
        finding("#{prefix}.env_file", "unmanaged environment files") if definition.key?("env_file")
        Array(definition["volumes"]).each do |volume|
          finding("#{prefix}.volumes", "host or Docker socket mount") if unsafe_volume?(volume)
        end
      end

      def inspect_namespaces(prefix, definition)
        %w[network_mode pid ipc].each do |key|
          finding("#{prefix}.#{key}", "host namespace access") if definition[key].to_s == "host"
        end
      end

      def inspect_capabilities(prefix, definition)
        capabilities = Array(definition["cap_add"]).map { |item| item.to_s.upcase }
        return unless capabilities.intersect?(%w[ALL SYS_ADMIN SYS_PTRACE NET_ADMIN])

        finding("#{prefix}.cap_add", "elevated Linux capabilities")
      end

      def inspect_ports(prefix, name, definition)
        return unless definition.key?("ports")
        return if name == @type && Array(definition["ports"]) == managed_ports

        finding("#{prefix}.ports", "ports outside the managed firewall model")
      end

      def managed_ports
        return [] unless @service.publish

        ["#{@service.bind}:#{@service.port}:#{container_port}"]
      end

      def unsafe_volume?(volume)
        source = case volume
                 when String then volume.split(":", 2).first
                 when Hash then volume["source"] || volume["src"]
                 end
        source.to_s.start_with?("/") || source.to_s.include?("docker.sock")
      end

      def finding(path, message)
        security_findings << { path: path, message: message }
      end

      def generated_document
        {
          "name" => project_name,
          "services" => { @type => generated_service_definition },
          "volumes" => { "data" => nil },
          "networks" => { "private" => { "external" => true, "name" => "kitsune-private" } }
        }
      end

      def generated_service_definition
        definition = @type == "postgres" ? postgres : redis
        definition["ports"] = ["#{@service.bind}:#{@service.port}:#{container_port}"] if @service.publish
        definition
      end

      def postgres
        {
          "image" => @service.image,
          "restart" => "unless-stopped",
          "environment" => {
            "POSTGRES_DB" => database,
            "POSTGRES_USER" => "postgres",
            "POSTGRES_PASSWORD" => interpolation
          },
          "volumes" => ["data:/var/lib/postgresql/data"],
          "networks" => ["private"],
          "healthcheck" => healthcheck("pg_isready -U postgres -d #{database}")
        }
      end

      def redis
        {
          "image" => @service.image,
          "restart" => "unless-stopped",
          "environment" => { "REDIS_PASSWORD" => interpolation },
          "command" => ["sh", "-ec", 'exec redis-server --appendonly yes --requirepass "$$REDIS_PASSWORD"'],
          "volumes" => ["data:/data"],
          "networks" => ["private"],
          "healthcheck" => healthcheck('REDISCLI_AUTH="$${REDIS_PASSWORD}" redis-cli ping | grep -Fxq PONG')
        }
      end

      def healthcheck(command)
        { "test" => ["CMD-SHELL", command], "interval" => "10s", "timeout" => "5s", "retries" => 12 }
      end

      def stringify_keys(value)
        case value
        when Hash then value.to_h { |key, item| [key.to_s, stringify_keys(item)] }
        when Array then value.map { |item| stringify_keys(item) }
        else value
        end
      end

      def project_name = "kitsune-#{@config.environment}-#{@type}"
      def database = "app_#{@config.environment.tr('-', '_')}"
      def container_port = @type == "postgres" ? 5432 : 6379
      def interpolation = "${#{@service.password_env}}"
    end
  end
end
