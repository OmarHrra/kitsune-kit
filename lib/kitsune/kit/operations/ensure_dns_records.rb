# frozen_string_literal: true

require "public_suffix"
require_relative "../adapters/provider"
require_relative "../errors"
require_relative "../plan"

module Kitsune
  module Kit
    module Operations
      class EnsureDnsRecords
        def initialize(config:, provider:, state_store:)
          @config = config
          @provider = provider
          @state_store = state_store
        end

        def plan
          server = find_server
          desired_ip = server&.public_ip
          entries = domains.map { |domain| plan_domain(domain, desired_ip) }
          action = entries.all? { |entry| entry[:action] == "no_change" } ? "no_change" : "update"
          Change.new(
            resource: "dns",
            action: action,
            summary: summary_for(action, entries),
            details: { records: entries, desired_ip: desired_ip, depends_on: desired_ip ? nil : "server" }
          )
        end

        def apply(change)
          return [] unless change.changed?

          server = find_server
          unless server&.public_ip
            raise Errors::VerificationError.new(
              "server has no public IP for DNS records",
              hint: "Wait for the server to become ready, then resume apply."
            )
          end

          domains.map do |domain|
            apply_domain(domain, server.public_ip).tap { |entry| save_record(entry) }
          end
        end

        def rollback
          managed = state_store.read(config.environment).dig("resources", "dns")
          return false unless managed

          managed.each_value do |entry|
            record = record_from_state(entry.fetch("record"))
            previous = entry["previous"] && record_from_state(entry["previous"])
            if previous
              provider.upsert_dns_record(record: previous)
            else
              provider.delete_dns_record(id: record.id, zone: record.zone)
            end
          end
          state_store.update(config.environment) do |state|
            state["resources"].delete("dns")
            state["operations"] << { "resource" => resource, "action" => "rollback", "status" => "applied" }
            state
          end
          true
        end

        def resource = "dns"

        private

        attr_reader :config, :provider, :state_store

        def domains = config.dns.domains

        def find_server
          provider.find_server(name: config.server.name, tags: config.server.tags)
        end

        def plan_domain(domain, desired_ip)
          zone, name = zone_and_name(domain)
          existing = provider.find_dns_record(zone: zone, name: name, type: "A")
          action = if existing && desired_ip && existing.data == desired_ip && existing.ttl == config.dns.ttl
                     "no_change"
                   elsif existing
                     "update"
                   else
                     "create"
                   end
          {
            domain: domain,
            zone: zone,
            name: name,
            action: action,
            current: existing&.to_h,
            desired: { data: desired_ip || "pending-server-ip", ttl: config.dns.ttl }
          }
        end

        def apply_domain(domain, ip)
          zone, name = zone_and_name(domain)
          existing = provider.find_dns_record(zone: zone, name: name, type: "A")
          desired = Adapters::DnsRecord.new(
            id: existing&.id,
            zone: zone,
            name: name,
            type: "A",
            data: ip,
            ttl: config.dns.ttl
          )
          saved = if existing&.data == ip && existing.ttl == config.dns.ttl
                    existing
                  else
                    provider.upsert_dns_record(record: desired)
                  end
          previous = prior_previous(domain, existing)
          { domain: domain, record: saved, previous: previous }
        end

        def zone_and_name(domain)
          parsed = PublicSuffix.parse(domain)
          zone = parsed.domain
          prefix = domain.delete_suffix(zone).delete_suffix(".")
          [zone, prefix.empty? ? "@" : prefix]
        rescue PublicSuffix::Error
          raise Errors::ConfigurationError.new(
            "cannot determine the DNS zone for #{domain}",
            hint: "Use a fully qualified public domain name."
          )
        end

        def save_record(entry)
          state_store.update(config.environment) do |state|
            state["resources"]["dns"] ||= {}
            state["resources"]["dns"][entry[:domain]] = {
              "record" => stringify(entry[:record].to_h),
              "previous" => entry[:previous] && stringify(entry[:previous].to_h)
            }
            state["operations"] << { "resource" => resource, "action" => "update", "status" => "applied" }
            state
          end
        end

        def prior_previous(domain, existing)
          prior = state_store.read(config.environment).dig("resources", "dns", domain)
          return existing unless prior

          prior["previous"] && record_from_state(prior["previous"])
        end

        def stringify(hash) = hash.transform_keys(&:to_s)

        def record_from_state(value)
          Adapters::DnsRecord.new(**value.transform_keys(&:to_sym))
        end

        def summary_for(action, entries)
          return "DNS records are current" if action == "no_change"

          "Apply #{entries.count { |entry| entry[:action] != 'no_change' }} DNS record change(s)"
        end
      end
    end
  end
end
