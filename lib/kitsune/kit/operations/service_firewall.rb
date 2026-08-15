# frozen_string_literal: true

require_relative "../errors"

module Kitsune
  module Kit
    module Operations
      class ServiceFirewall
        attr_reader :owned_rules, :drop_owned

        def initialize(config:, type:, service:, transport:, state_store:, resource:)
          @config = config
          @type = type
          @service = service
          @transport = transport
          @state_store = state_store
          @resource = resource
          @owned_rules = []
          @drop_owned = false
        end

        def reconcile(previous)
          unless service.publish
            remove_state(previous)
            return
          end

          @transaction_added = []
          @transaction_deleted = []
          ensure_drop_rule(previous, tracked: true)
          added = service.allowed_cidrs.reject { |cidr| rule_exists?(allow_rule(cidr)) }.each do |cidr|
            add_tracked_rule(allow_rule(cidr))
          end
          retained = previous_rules_for_current_port(previous) & service.allowed_cidrs
          @owned_rules = (retained + added).uniq
          remove_stale(previous, tracked: true)
        rescue StandardError => e
          begin
            rollback_transaction
          rescue StandardError => recovery_error
            raise Errors::VerificationError.new(
              "Docker firewall reconciliation and recovery both failed",
              hint: "Inspect DOCKER-USER rules marked by Kitsune Kit before retrying.",
              context: {
                original_error: error_name(e), recovery_error: error_name(recovery_error)
              }
            )
          end
          raise e
        ensure
          @transaction_added = nil
          @transaction_deleted = nil
        end

        def remove
          remove_state(managed_state)
        end

        def restore(previous)
          return unless previous["published"]

          port = previous.fetch("port")
          ensure_rule(drop_rule(port: port))
          previous.fetch("firewall_rules_added", []).each do |cidr|
            ensure_rule(allow_rule(cidr, port: port))
          end
        end

        def restore_after_failure(previous)
          remove_state(
            "published" => service.publish,
            "port" => service.port,
            "firewall_rules_added" => @owned_rules,
            "firewall_drop_added" => @drop_owned
          )
          restore(previous || {})
        end

        private

        attr_reader :config, :type, :service, :transport, :state_store, :resource

        def ensure_drop_rule(previous, tracked: false)
          existed = rule_exists?(drop_rule)
          unless existed
            tracked ? add_tracked_rule(drop_rule) : add_rule(drop_rule, position: 1)
          end
          previously_owned = previous&.fetch("published", false) && previous.fetch("port") == service.port &&
                             previous["firewall_drop_added"]
          @drop_owned = previously_owned || !existed
        end

        def remove_state(previous)
          return unless previous&.fetch("published", false)

          port = previous.fetch("port")
          previous.fetch("firewall_rules_added", []).each { |cidr| delete_rule(allow_rule(cidr, port: port)) }
          delete_rule(drop_rule(port: port)) if previous["firewall_drop_added"]
        end

        def remove_stale(previous, tracked: false)
          return unless previous&.fetch("published", false)

          previous_port = previous.fetch("port")
          previous.fetch("firewall_rules_added", []).each do |cidr|
            next if previous_port == service.port && service.allowed_cidrs.include?(cidr)

            rule = allow_rule(cidr, port: previous_port)
            tracked ? delete_tracked_rule(rule) : delete_rule(rule)
          end
          return unless previous["firewall_drop_added"] && previous_port != service.port

          rule = drop_rule(port: previous_port)
          tracked ? delete_tracked_rule(rule) : delete_rule(rule)
        end

        def previous_rules_for_current_port(previous)
          return [] unless previous&.fetch("published", false) && previous.fetch("port") == service.port

          previous.fetch("firewall_rules_added", [])
        end

        def allow_rule(cidr, port: service.port)
          common_rule(port) + ["-s", cidr, "-m", "comment", "--comment", "kitsune:#{type}:allow", "-j", "ACCEPT"]
        end

        def drop_rule(port: service.port)
          common_rule(port) + ["-m", "comment", "--comment", "kitsune:#{type}:drop", "-j", "DROP"]
        end

        def common_rule(port)
          ["DOCKER-USER", "-p", "tcp", "-m", "conntrack", "--ctorigdstport", port.to_s,
           "--ctdir", "ORIGINAL"]
        end

        def ensure_rule(rule)
          add_rule(rule, position: 1) unless rule_exists?(rule)
        end

        def rule_exists?(rule)
          transport.execute("sudo", arguments: ["iptables", "-C", *rule], timeout: 20).success?
        end

        def add_rule(rule, position:)
          result = transport.execute(
            "sudo",
            arguments: ["iptables", "-I", rule.first, position.to_s, *rule.drop(1)],
            timeout: 20
          )
          raise_remote!(result, "add Docker firewall rule")
        end

        def add_tracked_rule(rule)
          add_rule(rule, position: 1)
          @transaction_added << rule
        end

        def delete_rule(rule)
          result = transport.execute("sudo", arguments: ["iptables", "-D", *rule], timeout: 20)
          return false if result.exit_status == 1

          raise_remote!(result, "remove Docker firewall rule") unless result.success?
          true
        end

        def delete_tracked_rule(rule)
          @transaction_deleted << rule if delete_rule(rule)
        end

        def rollback_transaction
          Array(@transaction_added).reverse_each { |rule| delete_rule(rule) }
          Array(@transaction_deleted).reverse_each { |rule| ensure_rule(rule) }
        end

        def error_name(error) = error.respond_to?(:code) ? error.code : error.class.name

        def managed_state = state_store.read(config.environment).dig("resources", resource)

        def raise_remote!(result, action)
          return if result.success?

          raise Errors::RemoteCommandError.new(
            "unable to #{action} for #{type}",
            context: { stderr: result.stderr, exit_status: result.exit_status }
          )
        end
      end
    end
  end
end
