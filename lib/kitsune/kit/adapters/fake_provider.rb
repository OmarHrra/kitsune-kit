# frozen_string_literal: true

require "securerandom"
require_relative "provider"

module Kitsune
  module Kit
    module Adapters
      class FakeProvider < Provider
        attr_reader :calls, :servers, :dns_records

        def initialize(servers: [], dns_records: [], failures: {})
          super()
          @servers = servers.dup
          @dns_records = dns_records.dup
          @failures = failures
          @calls = []
        end

        def validate_credentials!
          record(:validate_credentials)
          fail_if_requested!(:validate_credentials)
          true
        end

        def validate_server_spec!(spec:)
          record(:validate_server_spec, spec: spec)
          fail_if_requested!(:validate_server_spec)
          true
        end

        def find_server(name:, tags: [])
          record(:find_server, name: name, tags: tags)
          fail_if_requested!(:find_server)
          @servers.find { |server| server.name == name && (tags.empty? || (tags - server.tags).empty?) }
        end

        def find_server_by_id(id:)
          record(:find_server_by_id, id: id)
          fail_if_requested!(:find_server_by_id)
          @servers.find { |server| server.id.to_s == id.to_s }
        end

        def create_server(spec:)
          record(:create_server, spec: spec)
          fail_if_requested!(:create_server)
          server = ServerRecord.new(
            id: SecureRandom.uuid,
            name: spec.fetch(:name),
            status: "new",
            public_ip: nil,
            region: spec.fetch(:region),
            size: spec.fetch(:size),
            image: spec.fetch(:image),
            tags: spec.fetch(:tags, [])
          )
          @servers << server
          server
        end

        def wait_until_ready(id:, timeout:)
          record(:wait_until_ready, id: id, timeout: timeout)
          fail_if_requested!(:wait_until_ready)
          server = @servers.find { |candidate| candidate.id == id }
          raise KeyError, "server not found: #{id}" unless server

          ready = server.with(status: "active", public_ip: server.public_ip || "203.0.113.10")
          @servers[@servers.index(server)] = ready
          ready
        end

        def delete_server(id:)
          record(:delete_server, id: id)
          fail_if_requested!(:delete_server)
          !!@servers.reject! { |server| server.id == id }
        end

        def find_dns_record(zone:, name:, type:)
          record(:find_dns_record, zone: zone, name: name, type: type)
          @dns_records.find { |record| record.zone == zone && record.name == name && record.type == type }
        end

        def upsert_dns_record(record:)
          record(:upsert_dns_record, record: record)
          existing = find_dns_record(zone: record.zone, name: record.name, type: record.type)
          saved = record.with(id: existing&.id || SecureRandom.uuid)
          existing ? @dns_records[@dns_records.index(existing)] = saved : @dns_records << saved
          saved
        end

        def delete_dns_record(id:, zone:)
          record(:delete_dns_record, id: id, zone: zone)
          !!@dns_records.reject! { |record| record.id == id && record.zone == zone }
        end

        private

        def record(name, **arguments) = @calls << [name, arguments]

        def fail_if_requested!(name)
          failure = @failures[name]
          raise failure if failure
        end
      end
    end
  end
end
