# frozen_string_literal: true

require "json"
require "yaml"

module Kitsune
  module Kit
    class ServiceCompose
      def initialize(config:, type:, service:)
        @config = config
        @type = type
        @service = service
      end

      def content = YAML.dump(document)
      def env_content(password) = "#{@service.password_env}=#{JSON.generate(password)}\n"

      private

      def document
        {
          "name" => project_name,
          "services" => { @type => service_definition },
          "volumes" => { "data" => nil },
          "networks" => { "private" => { "external" => true, "name" => "kitsune-private" } }
        }
      end

      def service_definition
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

      def project_name = "kitsune-#{@config.environment}-#{@type}"
      def database = "app_#{@config.environment.tr('-', '_')}"
      def container_port = @type == "postgres" ? 5432 : 6379
      def interpolation = "${#{@service.password_env}}"
    end
  end
end
