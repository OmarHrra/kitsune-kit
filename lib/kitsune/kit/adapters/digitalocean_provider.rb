# frozen_string_literal: true

require "droplet_kit"
require_relative "../errors"
require_relative "provider"

module Kitsune
  module Kit
    module Adapters
      class DigitalOceanProvider < Provider
        POLL_INTERVAL = 5

        def initialize(token:, client: nil, sleeper: Kernel, maximum_timeout: nil)
          super()
          raise Errors::AuthenticationError, "DigitalOcean token is missing" if token.to_s.empty?
          if maximum_timeout && maximum_timeout <= 0
            raise Errors::ConfigurationError, "timeout must be greater than zero"
          end

          @client = client || build_client(token, maximum_timeout)
          @sleeper = sleeper
        end

        def validate_credentials!
          @client.account.info
          true
        rescue StandardError => e
          raise_provider_error(
            "DigitalOcean authentication failed",
            e,
            authentication: true,
            hint: "Use a current token for the selected team and include the account:read scope."
          )
        end

        def validate_server_spec!(spec:)
          validate_region!(spec)
          validate_size!(spec)
          validate_image!(spec)
          true
        rescue Errors::ConfigurationError
          raise
        rescue StandardError => e
          raise_provider_error("Unable to validate DigitalOcean server configuration", e)
        end

        def find_server(name:, tags: [])
          tag = tags.first
          droplets = tag ? @client.droplets.all(tag_name: tag) : @client.droplets.all
          droplet = droplets.find do |candidate|
            candidate.name == name && (tags - Array(candidate.tags)).empty?
          end
          droplet && server_record(droplet)
        rescue StandardError => e
          raise_provider_error("Unable to find DigitalOcean server #{name}", e)
        end

        def find_server_by_id(id:)
          server_record(@client.droplets.find(id: id))
        rescue StandardError => e
          return nil if not_found?(e)

          raise_provider_error("Unable to find DigitalOcean server #{id}", e)
        end

        def create_server(spec:)
          droplet = DropletKit::Droplet.new(
            name: spec.fetch(:name),
            region: spec.fetch(:region),
            size: spec.fetch(:size),
            image: spec.fetch(:image),
            ssh_keys: [spec.fetch(:ssh_key_id)],
            tags: spec.fetch(:tags, [])
          )
          server_record(@client.droplets.create(droplet))
        rescue StandardError => e
          raise_provider_error("Unable to create DigitalOcean server #{spec[:name]}", e)
        end

        def wait_until_ready(id:, timeout: 180)
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
          loop do
            droplet = @client.droplets.find(id: id)
            record = server_record(droplet)
            return record if record.status == "active" && record.public_ip
            break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

            @sleeper.sleep(POLL_INTERVAL)
          end
          raise Errors::TimeoutError.new(
            "DigitalOcean server #{id} did not become ready within #{timeout} seconds",
            hint: "Inspect the Droplet in DigitalOcean before retrying."
          )
        rescue Errors::Error
          raise
        rescue StandardError => e
          raise_provider_error("Unable to wait for DigitalOcean server #{id}", e)
        end

        def delete_server(id:)
          @client.droplets.delete(id: id)
          true
        rescue StandardError => e
          raise_provider_error("Unable to delete DigitalOcean server #{id}", e)
        end

        def find_dns_record(zone:, name:, type:)
          record = @client.domain_records.all(for_domain: zone).find do |candidate|
            candidate.name == name && candidate.type == type
          end
          record && dns_record(zone, record)
        rescue StandardError => e
          raise_provider_error("Unable to inspect DNS record #{name}.#{zone}", e)
        end

        def upsert_dns_record(record:)
          value = DropletKit::DomainRecord.new(type: record.type, name: record.name, data: record.data, ttl: record.ttl)
          saved = if record.id
                    @client.domain_records.update(value, for_domain: record.zone, id: record.id)
                  else
                    @client.domain_records.create(value, for_domain: record.zone)
                  end
          dns_record(record.zone, saved)
        rescue StandardError => e
          raise_provider_error("Unable to update DNS record #{record.name}.#{record.zone}", e)
        end

        def delete_dns_record(id:, zone:)
          @client.domain_records.delete(for_domain: zone, id: id)
          true
        rescue StandardError => e
          raise_provider_error("Unable to delete DNS record #{id} from #{zone}", e)
        end

        private

        def build_client(token, maximum_timeout)
          return DropletKit::Client.new(access_token: token) unless maximum_timeout

          DropletKit::Client.new(
            access_token: token, open_timeout: maximum_timeout, timeout: maximum_timeout
          )
        end

        def server_record(droplet)
          ip = droplet.networks&.v4&.find { |network| network.type == "public" }&.ip_address
          ServerRecord.new(
            id: droplet.id.to_s,
            name: droplet.name,
            status: droplet.status,
            public_ip: ip,
            region: droplet.region.respond_to?(:slug) ? droplet.region.slug : droplet.region.to_s,
            size: droplet.size_slug || droplet.size&.slug,
            image: droplet.image.respond_to?(:slug) ? droplet.image.slug : droplet.image.to_s,
            tags: droplet.tags || []
          )
        end

        def dns_record(zone, record)
          DnsRecord.new(
            id: record.id.to_s,
            zone: zone,
            name: record.name,
            type: record.type,
            data: record.data,
            ttl: record.ttl
          )
        end

        def raise_provider_error(message, cause, authentication: false, hint: nil)
          error_class = authentication ? Errors::AuthenticationError : Errors::ProviderError
          raise error_class.new(
            message,
            hint: hint || "Check provider credentials, connectivity and resource limits, then retry.",
            context: { cause: cause.class.name },
            retryable: !authentication
          )
        end

        def not_found?(error)
          error.respond_to?(:response) && error.response.respond_to?(:status) && error.response.status.to_i == 404
        end

        def validate_region!(spec)
          region = @client.regions.all.find { |candidate| candidate.slug == spec.fetch(:region) }
          return if region&.available

          raise unavailable("region", spec[:region], "Choose an available DigitalOcean region.")
        end

        def validate_size!(spec)
          size = @client.sizes.all.find { |candidate| candidate.slug == spec.fetch(:size) }
          return if size&.available && Array(size.regions).include?(spec[:region])

          raise unavailable("size", spec[:size], "Choose a size available in region #{spec[:region]}.")
        end

        def validate_image!(spec)
          image = @client.images.all(type: "distribution").find do |candidate|
            candidate.slug == spec.fetch(:image)
          end
          return if image && (Array(image.regions).empty? || Array(image.regions).include?(spec[:region]))

          raise unavailable("image", spec[:image], "Choose a supported image available in #{spec[:region]}.")
        end

        def unavailable(field, value, hint)
          Errors::ConfigurationError.new(
            "DigitalOcean #{field} is unavailable: #{value}",
            hint: hint,
            context: { field: field, value: value }
          )
        end
      end
    end
  end
end
