require "droplet_kit"
require "thor"

module Kitsune
  module Kit
    module Commands
      class Dns < Thor
        namespace "dns"

        class_option :domains, type: :string, desc: "Comma-separated domain list (or from ENV['DOMAIN_NAMES'])"
        class_option :server_ip, type: :string, required: true, desc: "IPv4 to assign to domain(s)"
        class_option :ttl, type: :numeric, default: 3600, desc: "TTL in seconds for DNS records"

        desc "link", "Link domains to a given IP using A records"
        def link
          validate_ip!

          domains = resolve_domains
          return if domains.empty?

          ip = options[:server_ip]
          ttl = ENV.fetch("DNS_TTL", options[:ttl]).to_i

          client = DropletKit::Client.new(access_token: ENV.fetch("DO_API_TOKEN"))

          domains.each do |fqdn|
            parts = fqdn.split('.')
            next if parts.size < 2

            root_domain = parts[-2..].join('.')
            subdomain = parts[0..-3].join('.')
            name_for_a = subdomain.empty? ? "@" : subdomain

            puts "\n🌐 Linking '#{fqdn}' to IP #{ip} (domain: #{root_domain}, record: #{name_for_a})"

            records = client.domain_records.all(for_domain: root_domain)
            existing = records.find { |r| r.type == "A" && r.name == name_for_a }

            domain_record = DropletKit::DomainRecord.new(
              type: "A",
              name: name_for_a,
              data: ip,
              ttl: ttl
            )

            msg = "'#{AnsiColor.colorize(name_for_a, color: :green)}.#{AnsiColor.colorize(root_domain, color: :green)}' → #{AnsiColor.colorize(ip, color: :light_cyan)}"
            if existing
              client.domain_records.update(
                domain_record,
                for_domain: root_domain,
                id: existing.id
              )
              puts "✅ Updated A record #{msg}"
            else
              client.domain_records.create(
                domain_record,
                for_domain: root_domain
              )
              puts "✅ Created A record #{msg}"
            end
          end
        end

        desc "rollback", "Remove A records for the specified domains"
        def rollback
          domains = resolve_domains
          return if domains.empty?

          client = DropletKit::Client.new(access_token: ENV.fetch("DO_API_TOKEN"))

          domains.each do |fqdn|
            parts = fqdn.split('.')
            next if parts.size < 2

            root_domain = parts[-2..].join('.')
            subdomain = parts[0..-3].join('.')
            name_for_a = subdomain.empty? ? "@" : subdomain

            puts "\n🗑️ Attempting to delete A record for '#{fqdn}' (domain: #{root_domain}, record: #{name_for_a})"

            records = client.domain_records.all(for_domain: root_domain)
            existing = records.find { |r| r.type == "A" && r.name == name_for_a }

            if existing
              client.domain_records.delete(for_domain: root_domain, id: existing.id)
              puts "✅ Deleted A record '#{name_for_a}.#{root_domain}'"
            else
              puts "💡 No A record found for '#{name_for_a}.#{root_domain}', nothing to delete"
            end
          end
        end

        no_commands do
          def validate_ip!
            if options[:server_ip].nil? || options[:server_ip].empty?
              abort "❌ Missing required option: --server-ip"
            end
          end

          def resolve_domains
            raw = options[:domains] || ENV["DOMAIN_NAMES"]
            if raw.nil? || raw.strip.empty?
              puts "⏭️  No domains provided. Skipping DNS operation."
              return []
            end
            raw.split(',').map(&:strip).reject(&:empty?)
          end
        end
      end
    end
  end
end
