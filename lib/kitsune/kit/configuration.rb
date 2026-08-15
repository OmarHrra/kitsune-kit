# frozen_string_literal: true

require "ipaddr"
require "pathname"
require "yaml"
require_relative "errors"

module Kitsune
  module Kit
    module Configuration
      SCHEMA_VERSION = 1
      SUPPORTED_PROVIDERS = ["digitalocean"].freeze
      SUPPORTED_IMAGES = %w[ubuntu-22-04-x64 ubuntu-24-04-x64].freeze

      class Provider < Data.define(:name, :token_env)
        def initialize(name: "digitalocean", token_env: "DO_API_TOKEN")
          super(name: name.to_s, token_env: token_env.to_s)
        end
      end

      class Server < Data.define(:name, :region, :size, :image, :ssh_key_id, :tags)
        def initialize(name:, region:, size:, image:, ssh_key_id:, tags: [])
          super(
            name: name.to_s,
            region: region.to_s,
            size: size.to_s,
            image: image.to_s,
            ssh_key_id: ssh_key_id.to_s,
            tags: Array(tags).map(&:to_s).freeze
          )
        end
      end

      class Ssh < Data.define(:user, :port, :key_path, :allowed_cidrs)
        def initialize(user: "deploy", port: 22, key_path: "~/.ssh/id_ed25519", allowed_cidrs: [])
          super(
            user: user.to_s,
            port: Integer(port),
            key_path: Pathname(key_path.to_s).expand_path.to_s,
            allowed_cidrs: Array(allowed_cidrs).map(&:to_s).freeze
          )
        rescue ArgumentError, TypeError
          raise Errors::ConfigurationError, "ssh.port must be an integer"
        end
      end

      class Compose < Data.define(:mode, :file, :allow_unsafe)
        MODES = %w[generated overlay custom].freeze

        def initialize(mode: "generated", file: nil, allow_unsafe: false, root: Dir.pwd)
          expanded_file = file.to_s.empty? ? nil : Pathname(file.to_s).expand_path(root).to_s
          super(mode: mode.to_s, file: expanded_file, allow_unsafe: boolean(allow_unsafe))
        end

        private

        def boolean(value)
          return value if [true, false].include?(value)
          return true if value.to_s.casecmp("true").zero?
          return false if value.to_s.casecmp("false").zero?

          raise Errors::ConfigurationError, "expected a boolean, got #{value.inspect}"
        end
      end

      class Service < Data.define(:enabled, :mode, :host, :image, :publish, :bind, :allowed_cidrs, :port,
                                  :password_env, :compose)
        def initialize(**attributes)
          super(
            enabled: boolean(attributes.fetch(:enabled)),
            mode: attributes.fetch(:mode, "managed").to_s,
            host: attributes[:host]&.to_s,
            image: attributes.fetch(:image).to_s,
            publish: boolean(attributes.fetch(:publish)),
            bind: attributes.fetch(:bind).to_s,
            allowed_cidrs: Array(attributes.fetch(:allowed_cidrs)).map(&:to_s).freeze,
            port: Integer(attributes.fetch(:port)),
            password_env: attributes.fetch(:password_env).to_s,
            compose: attributes.fetch(:compose, Compose.new)
          )
        rescue ArgumentError, TypeError
          raise Errors::ConfigurationError, "service port must be an integer"
        end

        private

        def boolean(value)
          return value if [true, false].include?(value)
          return true if value.to_s.casecmp("true").zero?
          return false if value.to_s.casecmp("false").zero?

          raise Errors::ConfigurationError, "expected a boolean, got #{value.inspect}"
        end
      end

      class Services < Data.define(:postgres, :redis); end

      class System < Data.define(:swap_size_gb, :swap_swappiness, :unattended_upgrades, :metrics,
                                 :metrics_installer_sha256)
        def initialize(swap_size_gb:, swap_swappiness:, unattended_upgrades:, metrics:,
                       metrics_installer_sha256: nil)
          super(
            swap_size_gb: Integer(swap_size_gb),
            swap_swappiness: Integer(swap_swappiness),
            unattended_upgrades: boolean(unattended_upgrades),
            metrics: boolean(metrics),
            metrics_installer_sha256: metrics_installer_sha256&.to_s
          )
        rescue ArgumentError, TypeError
          raise Errors::ConfigurationError, "system numeric values must be integers"
        end

        private

        def boolean(value)
          return value if [true, false].include?(value)

          raise Errors::ConfigurationError, "expected a boolean, got #{value.inspect}"
        end
      end

      class Dns < Data.define(:domains, :ttl)
        def initialize(domains:, ttl:)
          super(domains: Array(domains).map(&:to_s).freeze, ttl: Integer(ttl))
        rescue ArgumentError, TypeError
          raise Errors::ConfigurationError, "dns.ttl must be an integer"
        end
      end

      class Config < Data.define(:version, :environment, :provider, :server, :ssh, :services, :system, :dns)
        def initialize(version:, environment:, provider:, server:, ssh:, services:, system:, dns:)
          super(
            version: Integer(version),
            environment: environment.to_s,
            provider: provider,
            server: server,
            ssh: ssh,
            services: services,
            system: system,
            dns: dns
          )
        end
      end

      DEFAULTS = {
        "version" => SCHEMA_VERSION,
        "provider" => { "name" => "digitalocean", "token_env" => "DO_API_TOKEN" },
        "server" => {
          "region" => "sfo3",
          "size" => "s-1vcpu-1gb",
          "image" => "ubuntu-24-04-x64",
          "tags" => ["kitsune-managed"]
        },
        "ssh" => { "user" => "deploy", "port" => 22, "key_path" => "~/.ssh/id_ed25519", "allowed_cidrs" => [] },
        "services" => {
          "postgres" => {
            "enabled" => false,
            "mode" => "managed",
            "host" => nil,
            "image" => "postgres:17",
            "publish" => false,
            "bind" => "127.0.0.1",
            "allowed_cidrs" => [],
            "port" => 5432,
            "password_env" => "POSTGRES_PASSWORD",
            "compose" => { "mode" => "generated", "file" => nil, "allow_unsafe" => false }
          },
          "redis" => {
            "enabled" => false,
            "mode" => "managed",
            "host" => nil,
            "image" => "redis:7.2",
            "publish" => false,
            "bind" => "127.0.0.1",
            "allowed_cidrs" => [],
            "port" => 6379,
            "password_env" => "REDIS_PASSWORD",
            "compose" => { "mode" => "generated", "file" => nil, "allow_unsafe" => false }
          }
        },
        "system" => {
          "swap_size_gb" => 2,
          "swap_swappiness" => 10,
          "unattended_upgrades" => true,
          "metrics" => false,
          "metrics_installer_sha256" => nil
        },
        "dns" => { "domains" => [], "ttl" => 3600 }
      }.freeze

      ENV_PATHS = {
        "KITSUNE_PROVIDER" => %w[provider name],
        "KITSUNE_SERVER_NAME" => %w[server name],
        "KITSUNE_REGION" => %w[server region],
        "KITSUNE_SIZE" => %w[server size],
        "KITSUNE_IMAGE" => %w[server image],
        "KITSUNE_SSH_KEY_ID" => %w[server ssh_key_id],
        "KITSUNE_SSH_USER" => %w[ssh user],
        "KITSUNE_SSH_PORT" => %w[ssh port],
        "KITSUNE_SSH_KEY_PATH" => %w[ssh key_path],
        "KITSUNE_METRICS_INSTALLER_SHA256" => %w[system metrics_installer_sha256]
      }.freeze

      SCHEMA_KEYS = {
        [] => %w[version provider server ssh services system dns],
        %w[provider] => %w[name token_env],
        %w[server] => %w[name region size image ssh_key_id tags],
        %w[ssh] => %w[user port key_path allowed_cidrs],
        %w[services] => %w[postgres redis],
        %w[services postgres] => %w[enabled mode host image publish bind allowed_cidrs port password_env compose],
        %w[services redis] => %w[enabled mode host image publish bind allowed_cidrs port password_env compose],
        %w[services postgres compose] => %w[mode file allow_unsafe],
        %w[services redis compose] => %w[mode file allow_unsafe],
        %w[system] => %w[swap_size_gb swap_swappiness unattended_upgrades metrics metrics_installer_sha256],
        %w[dns] => %w[domains ttl]
      }.freeze

      class Loader
        def initialize(root: Dir.pwd, env: ENV, config_path: nil)
          @root = Pathname(root).expand_path
          @env = env
          @config_path = config_path ? Pathname(config_path).expand_path : @root.join(".kitsune/config.yml")
        end

        def load(environment: nil, overrides: {})
          selected_environment = (environment || @env["KITSUNE_ENV"] || selected_environment_from_file ||
                                  "development").to_s
          unless selected_environment.match?(/\A[a-z0-9][a-z0-9_-]*\z/)
            raise Errors::ConfigurationError, "environment name has an invalid format"
          end

          project = load_yaml(@config_path, required: true)
          environment_config = load_yaml(@root.join(".kitsune/environments/#{selected_environment}.yml"),
                                         required: false)
          combined = deep_merge(DEFAULTS, project)
          combined = deep_merge(combined, environment_config)
          combined = apply_environment(combined)
          combined = deep_merge(combined, stringify_keys(overrides))
          build(combined, selected_environment)
        end

        private

        def selected_environment_from_file
          path = @root.join(".kitsune/environment")
          return unless path.file?

          path.read.strip
        end

        def load_yaml(path, required:)
          unless path.file?
            return {} unless required

            raise Errors::ConfigurationError.new(
              "configuration file not found: #{path}",
              hint: "Run `kit init` in the project root."
            )
          end

          content = YAML.safe_load_file(path, permitted_classes: [], permitted_symbols: [], aliases: false)
          return {} if content.nil?
          raise Errors::ConfigurationError, "#{path} must contain a YAML mapping" unless content.is_a?(Hash)

          stringify_keys(content)
        rescue Psych::Exception => e
          raise Errors::ConfigurationError.new("invalid YAML in #{path}: #{e.message}",
                                               hint: "Correct the YAML syntax.")
        end

        def apply_environment(config)
          ENV_PATHS.each_with_object(deep_copy(config)) do |(name, path), result|
            set_path(result, path, @env[name]) if @env.key?(name)
          end
        end

        def build(data, environment)
          validate_structure!(data)
          validate_schema_version!(data["version"])
          config = Config.new(
            version: data.fetch("version"),
            environment: environment,
            provider: Provider.new(**symbolize(data.fetch("provider"))),
            server: Server.new(**symbolize(data.fetch("server"))),
            ssh: Ssh.new(**symbolize(data.fetch("ssh"))),
            services: Services.new(
              postgres: build_service(data.dig("services", "postgres")),
              redis: build_service(data.dig("services", "redis"))
            ),
            system: System.new(**symbolize(data.fetch("system"))),
            dns: Dns.new(**symbolize(data.fetch("dns")))
          )
          Validator.new(config, env: @env, root: @root).validate!
          config
        rescue KeyError => e
          raise Errors::ConfigurationError.new("missing configuration value: #{e.key}",
                                               hint: "Run `kit doctor` for details.")
        end

        def validate_structure!(data)
          errors = SCHEMA_KEYS.each_with_object([]) do |(path, known), findings|
            value = path.reduce(data) { |current, key| current.is_a?(Hash) ? current[key] : nil }
            label = path.empty? ? "configuration" : path.join(".")
            unless value.is_a?(Hash)
              findings << "#{label} must be a mapping"
              next
            end

            unknown = value.keys - known
            findings << "#{label} contains unknown keys: #{unknown.join(', ')}" if unknown.any?
          end
          return if errors.empty?

          raise Errors::ConfigurationError.new(
            "invalid configuration structure:\n- #{errors.join("\n- ")}",
            hint: "Remove unknown keys and restore every documented YAML mapping."
          )
        end

        def build_service(data)
          attributes = symbolize(data)
          compose = Compose.new(**symbolize(data.fetch("compose")), root: @root)
          Service.new(**attributes, compose: compose)
        end

        def validate_schema_version!(version)
          return if version == SCHEMA_VERSION

          raise Errors::ConfigurationError.new(
            "unsupported configuration schema version #{version.inspect}; expected #{SCHEMA_VERSION}",
            hint: "Use a Kitsune Kit version that supports this schema or migrate a backup with documented tooling."
          )
        end

        def deep_merge(left, right)
          left.merge(right) do |_key, old_value, new_value|
            old_value.is_a?(Hash) && new_value.is_a?(Hash) ? deep_merge(old_value, new_value) : new_value
          end
        end

        def deep_copy(value) = Marshal.load(Marshal.dump(value))

        def set_path(hash, path, value)
          path[0...-1].reduce(hash) { |current, key| current[key] ||= {} }[path.last] = value
        end

        def stringify_keys(value)
          case value
          when Hash
            value.to_h { |key, item| [key.to_s, stringify_keys(item)] }
          when Array
            value.map { |item| stringify_keys(item) }
          else
            value
          end
        end

        def symbolize(hash) = hash.to_h { |key, value| [key.to_sym, value] }
      end

      class Validator
        RESOURCE_NAME = /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/
        ENV_NAME = /\A[A-Z][A-Z0-9_]*\z/
        SSH_USER = /\A[a-z_][a-z0-9_-]{0,31}\z/
        IMAGE = %r{\A[a-z0-9]+(?:[._/-][a-z0-9]+)*(?::[a-zA-Z0-9][a-zA-Z0-9._-]*)?(?:@sha256:[a-f0-9]{64})?\z}
        INSECURE_SECRETS = %w[password postgres redis changeme change-me secret admin].freeze

        def initialize(config, env: ENV, root: Dir.pwd)
          @config = config
          @env = env
          @root = Pathname(root).expand_path
          @errors = []
        end

        def validate!
          validate_provider
          validate_server
          validate_ssh
          validate_service("postgres", @config.services.postgres)
          validate_service("redis", @config.services.redis)
          validate_system
          validate_dns
          return @config if @errors.empty?

          raise Errors::ConfigurationError.new(
            "invalid configuration:\n- #{@errors.join("\n- ")}",
            hint: "Correct .kitsune/config.yml or the selected environment file."
          )
        end

        private

        def validate_provider
          unless SUPPORTED_PROVIDERS.include?(@config.provider.name)
            @errors << "provider.name must be one of: #{SUPPORTED_PROVIDERS.join(', ')}"
          end
          return if @config.provider.token_env.match?(ENV_NAME)

          @errors << "provider.token_env must be an environment variable name"
        end

        def validate_server
          server = @config.server
          @errors << "server.name is required" if server.name.empty?
          @errors << "server.name has an invalid format" unless server.name.match?(RESOURCE_NAME)
          @errors << "server.region is required" if server.region.empty?
          @errors << "server.size is required" if server.size.empty?
          @errors << "server.image is unsupported" unless SUPPORTED_IMAGES.include?(server.image)
          @errors << "server.ssh_key_id is required" if server.ssh_key_id.empty?
        end

        def validate_ssh
          ssh = @config.ssh
          @errors << "ssh.user has an invalid format" unless ssh.user.match?(SSH_USER)
          @errors << "ssh.port must be between 1 and 65535" unless (1..65_535).cover?(ssh.port)
          validate_private_key(ssh.key_path)
          ssh.allowed_cidrs.each { |cidr| validate_cidr("ssh.allowed_cidrs", cidr) }
        end

        def validate_private_key(path)
          unless File.file?(path)
            @errors << "ssh.key_path does not exist or is not a regular file: #{path}"
            return
          end

          mode = File.stat(path).mode & 0o777
          @errors << format("ssh.key_path permissions must be 0600 or stricter (currently %<mode>04o)", mode: mode) if
            mode.anybits?(0o077)
        rescue SystemCallError => e
          @errors << "ssh.key_path cannot be inspected: #{e.class}"
        end

        def validate_service(name, service)
          @errors << "services.#{name}.port must be between 1 and 65535" unless (1..65_535).cover?(service.port)
          @errors << "services.#{name}.password_env has an invalid format" unless service.password_env.match?(ENV_NAME)
          unless %w[managed external].include?(service.mode)
            @errors << "services.#{name}.mode must be managed or external"
          end
          if service.mode == "external"
            validate_external_service(name, service)
          else
            validate_managed_service(name, service)
          end
          validate_compose(name, service)
          validate_service_secret(name, service) if service.enabled
        end

        def validate_compose(name, service)
          compose = service.compose
          return invalid_compose_mode(name) unless Compose::MODES.include?(compose.mode)

          validate_compose_ownership(name, service)
          return validate_generated_compose(name, compose) if compose.mode == "generated"
          return missing_compose_file(name, compose) unless compose.file

          validate_compose_file(name, Pathname(compose.file))
        rescue SystemCallError => e
          @errors << "services.#{name}.compose.file cannot be inspected: #{e.class}"
        end

        def invalid_compose_mode(name)
          @errors << "services.#{name}.compose.mode must be generated, overlay or custom"
        end

        def validate_compose_ownership(name, service)
          return unless service.mode == "external" && service.compose.mode != "generated"

          @errors << "services.#{name}.compose is only available in managed mode"
        end

        def validate_generated_compose(name, compose)
          @errors << "services.#{name}.compose.file must be empty in generated mode" if compose.file
          return unless compose.allow_unsafe

          @errors << "services.#{name}.compose.allow_unsafe must be false in generated mode"
        end

        def missing_compose_file(name, compose)
          @errors << "services.#{name}.compose.file is required in #{compose.mode} mode"
        end

        def validate_compose_file(name, path)
          root_prefix = "#{@root}#{File::SEPARATOR}"
          return @errors << "services.#{name}.compose.file must stay inside the project root" unless
            path.to_s.start_with?(root_prefix)

          if path.symlink?
            @errors << "services.#{name}.compose.file must not be a symbolic link"
          elsif !path.file?
            @errors << "services.#{name}.compose.file does not exist or is not a regular file: #{path}"
          elsif !path.realpath.to_s.start_with?("#{@root.realpath}#{File::SEPARATOR}")
            @errors << "services.#{name}.compose.file must not resolve outside the project root"
          elsif path.size > 262_144
            @errors << "services.#{name}.compose.file must not exceed 256 KiB"
          end
        end

        def validate_managed_service(name, service)
          @errors << "services.#{name}.image has an invalid format" unless service.image.match?(IMAGE)
          @errors << "services.#{name}.host is only valid in external mode" unless service.host.to_s.empty?
          validate_bind(name, service.bind)
          service.allowed_cidrs.each { |cidr| validate_cidr("services.#{name}.allowed_cidrs", cidr) }
          return unless service.publish && service.allowed_cidrs.empty?

          @errors << "services.#{name}.allowed_cidrs is required when publish is true"
        end

        def validate_external_service(name, service)
          unless valid_endpoint_host?(service.host)
            @errors << "services.#{name}.host must be a valid hostname or IP address in external mode"
          end
          @errors << "services.#{name}.publish must be false in external mode" if service.publish
          return if service.allowed_cidrs.empty?

          @errors << "services.#{name}.allowed_cidrs must be empty in external mode"
        end

        def validate_service_secret(name, service)
          secret = @env.fetch(service.password_env, "")
          return @errors << "#{service.password_env} is required when services.#{name}.enabled is true" if
            secret.empty?
          return @errors << "#{service.password_env} uses a known insecure default value" if
            INSECURE_SECRETS.include?(secret.downcase)
          return unless secret.bytesize < 12

          @errors << "#{service.password_env} must contain at least 12 bytes"
        end

        def validate_bind(name, bind)
          address = IPAddr.new(bind)
          @errors << "services.#{name}.bind must be an IPv4 address" unless address.ipv4?
        rescue IPAddr::InvalidAddressError
          @errors << "services.#{name}.bind must be an IP address"
        end

        def valid_endpoint_host?(host)
          return false if host.to_s.empty?

          IPAddr.new(host)
          true
        rescue IPAddr::InvalidAddressError
          valid_hostname?(host)
        end

        def validate_system
          system = @config.system
          @errors << "system.swap_size_gb must be between 0 and 64" unless (0..64).cover?(system.swap_size_gb)
          @errors << "system.swap_swappiness must be between 0 and 100" unless (0..100).cover?(system.swap_swappiness)
          return unless system.metrics && !system.metrics_installer_sha256.to_s.match?(/\A[a-f0-9]{64}\z/)

          @errors << "system.metrics_installer_sha256 must be a lowercase SHA-256 when metrics is enabled"
        end

        def validate_dns
          @errors << "dns.ttl must be between 30 and 86400" unless (30..86_400).cover?(@config.dns.ttl)
          @config.dns.domains.each do |domain|
            @errors << "invalid DNS name: #{domain}" unless valid_hostname?(domain)
          end
        end

        def validate_cidr(field, cidr)
          IPAddr.new(cidr)
        rescue IPAddr::InvalidAddressError
          @errors << "#{field} contains an invalid CIDR: #{cidr}"
        end

        def valid_hostname?(hostname)
          return false if hostname.length > 253

          hostname.split(".").all? { |label| label.match?(RESOURCE_NAME) }
        end
      end
    end
  end
end
