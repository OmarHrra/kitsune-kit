# frozen_string_literal: true

module Kitsune
  module Kit
    module Adapters
      API_VERSION = 1

      ServerRecord = Data.define(:id, :name, :status, :public_ip, :region, :size, :image, :tags) do
        def to_h
          members.to_h { |member| [member, public_send(member)] }
        end
      end

      DnsRecord = Data.define(:id, :zone, :name, :type, :data, :ttl) do
        def to_h
          members.to_h { |member| [member, public_send(member)] }
        end
      end

      class Provider
        def validate_credentials! = raise NotImplementedError
        def validate_server_spec!(spec:) = raise NotImplementedError
        def find_server(name:, tags: []) = raise NotImplementedError
        def find_server_by_id(id:) = raise NotImplementedError
        def create_server(spec:) = raise NotImplementedError
        def wait_until_ready(id:, timeout:) = raise NotImplementedError
        def delete_server(id:) = raise NotImplementedError
        def find_dns_record(zone:, name:, type:) = raise NotImplementedError
        def upsert_dns_record(record:) = raise NotImplementedError
        def delete_dns_record(id:, zone:) = raise NotImplementedError
      end
    end
  end
end
