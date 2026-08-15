# frozen_string_literal: true

require "thor"
require_relative "../kit"

module Kitsune
  module Kit
    class CLI < Thor
      package_name "Kitsune Kit"

      # Thor may add framework-level commands between minor releases. Keep the
      # Keep the Kitsune Kit public surface intentional instead of inheriting those commands.
      remove_task :tree if all_tasks.key?("tree")

      class_option :env, type: :string, aliases: "-e", desc: "Environment name"
      class_option :root, type: :string, default: Dir.pwd, desc: "Project root"
      class_option :config, type: :string, desc: "Alternative project configuration file"
      class_option :format, type: :string, default: "human", enum: %w[human json], desc: "Output format"
      class_option :no_color, type: :boolean, default: false, desc: "Disable ANSI colors"
      class_option :no_input, type: :boolean, default: false, desc: "Fail instead of prompting"
      class_option :yes, type: :boolean, default: false, desc: "Approve non-destructive changes"
      class_option :dry_run, type: :boolean, default: false, desc: "Build and display a plan without applying"
      class_option :quiet, type: :boolean, default: false, desc: "Show only warnings, errors and final results"
      class_option :verbose, type: :boolean, default: false, desc: "Show additional operational details"
      class_option :debug, type: :boolean, default: false, desc: "Show technical error details"
      class_option :log, type: :boolean, default: true, desc: "Write redacted local execution logs"
      class_option :timeout, type: :numeric, desc: "Maximum seconds allowed for each remote step"
      class_option :trust_host_key, type: :string, desc: "Trust this exact SHA256 SSH host-key fingerprint"

      def self.exit_on_failure? = true

      def self.start(given_args = ARGV, config = {})
        config[:shell] ||= Thor::Base.shell.new
        dispatch(nil, normalized_arguments(given_args), nil, config)
      rescue Thor::Error => e
        config[:debug] || ENV["THOR_DEBUG"] == "1" ? raise(e) : config[:shell].error(e.message)

        exit(2)
      rescue Errno::EPIPE
        exit(0)
      end

      def self.normalized_arguments(arguments)
        values = arguments.dup
        return ["help", values.first] if values.length == 2 && values.last == "help" && tasks.key?(values.first)

        values
      end

      desc "version", "Print the Kitsune Kit version"
      def version
        puts "Kitsune Kit #{VERSION}"
      end

      map %w[-v --version] => :version

      desc "init", "Create a new .kitsune project configuration"
      option :force, type: :boolean, default: false, desc: "Replace generated configuration files"
      def init
        execute do
          files = Workflows::InitializeProject.new(root: options[:root]).call(force: options[:force])
          if json?
            flush_json(build_reporter(build_secret_filter), Result.success(files), "init", "development")
          else
            puts "Created Kitsune Kit configuration:"
            files.each { |file| puts "  #{file}" }
            puts "Next: edit .kitsune/config.yml, export DO_API_TOKEN, then run `kit doctor`."
          end
          0
        end
      end

      desc "doctor", "Check configuration, credentials and managed resources without changing them"
      def doctor
        execute do
          app, reporter = build_application
          result = Workflows::Doctor.new(
            config: app.config,
            provider: app.provider,
            state_store: app.state_store,
            transport_factory: app.transport_factory,
            operations: app.operations,
            event_bus: app.event_bus
          ).call
          if json?
            flush_json(reporter, result, "doctor", app.config.environment)
          else
            puts
            print_checks(result.value)
          end
          result.success? ? 0 : 1
        end
      end

      desc "plan", "Inspect infrastructure changes without applying them"
      def plan
        execute do
          app, reporter = build_application
          result = Workflows::BuildPlan.new(
            config: app.config,
            operations: app.operations,
            event_bus: app.event_bus
          ).call
          json? ? flush_json(reporter, result, "plan", app.config.environment) : print_plan(result.value)
          0
        end
      end

      desc "apply", "Apply the desired infrastructure configuration"
      def apply
        execute do
          app, reporter = build_application
          plan_result = Workflows::BuildPlan.new(
            config: app.config,
            operations: app.operations,
            event_bus: app.event_bus
          ).call
          plan = plan_result.value
          print_plan(plan) unless json?

          if options[:dry_run]
            render_apply_terminal(reporter, plan_result, app, "Dry run: no changes were applied.")
            next 0
          end

          unless plan.changed?
            result = Result.success([], metadata: { unchanged: true })
            render_apply_terminal(reporter, result, app, "No changes to apply.")
            next 0
          end

          confirm_apply!(plan)
          result = Workflows::ApplyPlan.new(
            config: app.config,
            operations: app.operations,
            state_store: app.state_store,
            event_bus: app.event_bus
          ).call(plan: plan)
          render_apply_success(reporter, result, app)
          0
        end
      end

      desc "resume [RUN_ID]", "Resume the latest failed or interrupted apply run"
      def resume(run_id = nil)
        execute do
          app, reporter = build_application
          confirm_resume!(run_id)
          result = Workflows::ApplyPlan.new(
            config: app.config,
            operations: app.operations,
            state_store: app.state_store,
            event_bus: app.event_bus
          ).call(resume_from: run_id || true)
          flush_json(reporter, result, "resume", app.config.environment) if json?
          0
        end
      end

      desc "status", "Show the current server and managed-resource state"
      def status
        execute do
          app, reporter = build_application
          result = Workflows::InspectEnvironment.new(
            config: app.config,
            provider: app.provider,
            state_store: app.state_store,
            event_bus: app.event_bus
          ).call
          if json?
            flush_json(reporter, result, "status", app.config.environment)
          else
            print_environment_status(result.value)
          end
          0
        end
      end

      desc "rollback", "Restore managed configuration while preserving the server and service data"
      def rollback
        execute do
          app, reporter = build_application
          confirm_named_action!("rollback", app.config.environment, option: :yes)
          result = Workflows::Rollback.new(
            config: app.config,
            operations: app.operations.drop(1),
            state_store: app.state_store,
            event_bus: app.event_bus
          ).call
          flush_json(reporter, result, "rollback", app.config.environment) if json?
          0
        end
      end

      desc "server ACTION", "Manage the server: show, create, configure, ssh, import, destroy"
      option :confirm_destroy, type: :string, desc: "Exact server name required for destruction"
      option :provider_id, type: :string, desc: "Exact provider ID required for state recovery"
      option :confirm_import, type: :string, desc: "Exact server name required for state import"
      def server(action)
        execute do
          app, reporter = build_application
          result = dispatch_server_action(app, action)
          flush_json(reporter, result, "server.#{action}", app.config.environment) if json? && result.is_a?(Result)
          0
        end
      end

      desc "service TYPE ACTION [SUBACTION]",
           "Manage postgres or redis, including Compose show, validate, diff and eject"
      option :confirm_destroy, type: :string, desc: "Exact TYPE@ENV value required for data destruction"
      option :backup_before_destroy, type: :boolean, default: false,
                                     desc: "Create a restricted remote data backup before destroy-data"
      option :force, type: :boolean, default: false, desc: "Replace an existing ejected Compose file and backup"
      def service(type, action, subaction = nil)
        execute do
          app, reporter = build_application
          result = if action == "compose"
                     dispatch_service_compose(app, type, subaction)
                   else
                     operation = find_service_operation(app, type, action)
                     dispatch_service_action(app, operation, type, action)
                   end
          if json? && result.is_a?(Result)
            command = ["service", type, action, subaction].compact.join(".")
            flush_json(reporter, result, command, app.config.environment)
          end
          0
        end
      end

      desc "dns ACTION", "Manage configured DNS records: list, plan, apply, remove"
      def dns(action)
        execute do
          app, reporter = build_application
          operation = app.operations.find { |candidate| candidate.resource == "dns" }
          raise Errors::ConfigurationError, "no DNS domains are configured" unless operation

          result = dispatch_resource_action(app, operation, action)
          flush_json(reporter, result, "dns.#{action}", app.config.environment) if json? && result.is_a?(Result)
          0
        end
      end

      desc "env ACTION [NAME]", "Manage environments: list, current, use NAME"
      def env(action, name = nil)
        execute do
          selection = Workflows::EnvironmentSelection.new(root: options[:root])
          value = case action
                  when "list" then selection.list
                  when "current" then selection.current
                  when "use" then selection.use(name)
                  else raise Errors::ConfigurationError, "unknown environment action: #{action}"
                  end
          if json?
            flush_json(
              build_reporter(build_secret_filter), Result.success(value), "env.#{action}", selection.current
            )
          elsif value.is_a?(Array)
            value.each { |environment| puts environment }
          else
            puts value
          end
          0
        end
      end

      desc "support ACTION", "Create local diagnostics: bundle"
      def support(action)
        execute do
          raise Errors::ConfigurationError, "unknown support action: #{action}" unless action == "bundle"

          app, = build_application
          filter = configured_secret_filter(app.config)
          doctor = Workflows::Doctor.new(
            config: app.config,
            provider: app.provider,
            state_store: app.state_store,
            transport_factory: app.transport_factory,
            operations: app.operations
          )
          path = Workflows::SupportBundle.new(
            root: options[:root], config: app.config, state_store: app.state_store, doctor: doctor,
            secret_filter: filter
          ).call
          if json?
            flush_json(
              build_reporter(filter), Result.success({ path: path }), "support.bundle", app.config.environment
            )
          else
            puts "Support bundle created: #{path}"
            puts "\nRedacted contents (inspect before sharing):"
            puts File.read(path)
            puts "Kitsune Kit did not upload anything."
          end
          0
        end
      end

      desc "docker ACTION", "Manage Docker: status, install, uninstall"
      def docker(action)
        execute do
          app, reporter = build_application
          operation = app.operations.find { |candidate| candidate.resource == "docker" }
          result = dispatch_docker_action(app, operation, action)
          flush_json(reporter, result, "docker.#{action}", app.config.environment) if json? && result.is_a?(Result)
          0
        end
      end

      desc "ui", "Open the interactive terminal interface"
      def ui
        execute do
          build_tui.call
        end
      end

      default_task :help

      no_commands do
        def execute
          status = yield
          exit(status) if status.is_a?(Integer) && !status.zero?
          status
        rescue Errors::Error => e
          render_error(e)
          exit(Errors.exit_status(e))
        rescue Interrupt
          warn "Cancelled."
          exit(130)
        rescue StandardError => e
          render_unexpected_error(e)
          exit(1)
        ensure
          puts "Log: #{@run_log_path}" if @run_log_path && !json?
        end

        def build_application
          filter = @secret_filter = build_secret_filter
          bus = Events::Bus.new
          reporter = build_reporter(filter)
          bus.subscribe(reporter)
          subscribe_logger(bus, filter)
          app = Application.build(
            root: options[:root],
            environment: options[:env],
            config_path: options[:config],
            event_bus: bus,
            host_key_confirmation: method(:confirm_host_key),
            maximum_timeout: options[:timeout]
          )
          register_configured_secrets(filter, app.config)
          [app, reporter]
        end

        def build_tui
          unless $stdin.tty? && $stdout.tty?
            raise Errors::ConfigurationError.new(
              "the TUI requires an interactive terminal",
              hint: "Use `kit doctor`, `kit plan`, `kit apply`, or --format json in automation."
            )
          end

          filter = @secret_filter = build_secret_filter
          bus = Events::Bus.new
          loader = Configuration::Loader.new(root: options[:root], env: ENV, config_path: options[:config])
          config = loader.load(environment: options[:env])
          store = Tui::Store.new(environment: config.environment, secret_filter: filter)
          bus.subscribe(store)
          subscribe_logger(bus, filter)
          app = Application.build(
            root: options[:root], environment: options[:env], config_path: options[:config], event_bus: bus,
            host_key_confirmation: method(:confirm_host_key), maximum_timeout: options[:timeout]
          )
          register_configured_secrets(filter, app.config)
          controller = Tui::Controller.new(store: store, actions: Tui::Actions.new(application: app))
          Tui::Application.new(store: store, controller: controller)
        end

        def build_secret_filter
          SecretFilter.new([ENV["DO_API_TOKEN"], ENV["POSTGRES_PASSWORD"], ENV["REDIS_PASSWORD"]])
        end

        def configured_secret_filter(config)
          build_secret_filter.tap { |filter| register_configured_secrets(filter, config) }
        end

        def build_reporter(filter)
          return Reporters::Json.new(secret_filter: filter) if json?

          Reporters::Human.new(color: !options[:no_color] && !ENV.key?("NO_COLOR"), quiet: options[:quiet],
                               verbose: options[:verbose], secret_filter: filter)
        end

        def flush_json(reporter, result, command, environment)
          reporter.flush(result: result, command: command, environment: environment)
        end

        def render_apply_terminal(reporter, result, app, human_message)
          return flush_json(reporter, result, "apply", app.config.environment) if json?

          puts human_message
        end

        def render_apply_success(reporter, result, app)
          return flush_json(reporter, result, "apply", app.config.environment) if json?

          puts "Next: run `kit doctor`; a subsequent `kit plan` should report zero changes."
        end

        def subscribe_logger(bus, filter)
          return unless options[:log]

          logger = RunLogger.new(root: options[:root], run_id: "session-#{SecureRandom.uuid}",
                                 secret_filter: filter)
          @run_log_path = logger.path
          bus.subscribe(logger)
        end

        def register_configured_secrets(filter, config)
          filter.register(ENV[config.provider.token_env])
          %w[postgres redis].each do |type|
            filter.register(ENV[config.services.public_send(type).password_env])
          end
        end

        def confirm_apply!(plan)
          if plan.destructive?
            raise Errors::UnsafeOperationError.new(
              "the plan contains destructive changes",
              hint: "Resolve or explicitly perform the required destructive operation first."
            )
          end
          return if options[:yes]
          if options[:no_input] || !$stdin.tty?
            raise Errors::UnsafeOperationError.new(
              "apply requires confirmation",
              hint: "Review `kit plan`, then pass --yes for a non-interactive apply."
            )
          end
          return if yes?("Apply #{plan.changed_count} change(s)? [y/N]")

          raise Errors::UnsafeOperationError, "apply was not confirmed"
        end

        def confirm_resume!(run_id)
          return if options[:yes]

          label = run_id || "the latest incomplete run"
          if options[:no_input] || !$stdin.tty?
            raise Errors::UnsafeOperationError.new(
              "resume requires confirmation",
              hint: "Inspect `kit status`, then pass --yes to resume #{label}."
            )
          end
          return if yes?("Resume #{label}? [y/N]")

          raise Errors::UnsafeOperationError, "resume was not confirmed"
        end

        def dispatch_server_action(app, action)
          case action
          when "show", "status" then inspect_environment(app)
          when "create" then apply_operations(app, [app.operations.first])
          when "configure" then apply_operations(app, app.operations.drop(1))
          when "import" then import_server(app)
          when "destroy" then destroy_server(app)
          when "ssh" then open_ssh(app)
          else raise Errors::ConfigurationError, "unknown server action: #{action}"
          end
        end

        def dispatch_service_action(app, operation, type, action)
          case action
          when "status" then service_status(app, type)
          when "install" then apply_operations(app, [operation])
          when "backup" then with_mutation_lock(app) { service_backup(operation) }
          when "remove"
            confirm_named_action!("remove #{type}", "#{type}@#{app.config.environment}", option: :yes)
            with_mutation_lock(app) { Result.success(operation.remove) }
          when "destroy-data" then destroy_service_data(app, operation, type)
          else raise Errors::ConfigurationError, "unknown service action: #{action}"
          end
        end

        def dispatch_service_compose(app, type, action)
          raise Errors::ConfigurationError, "unknown service type: #{type}" unless %w[postgres redis].include?(type)

          service = app.config.services.public_send(type)
          if service.mode == "external"
            raise Errors::UnsafeOperationError, "Compose is not managed for an external #{type} service"
          end

          compose = ServiceCompose.new(config: app.config, type: type, service: service)
          case action
          when "show" then compose_show(compose)
          when "validate" then compose_validate(type, compose)
          when "diff" then compose_diff(app, type, compose)
          when "eject" then compose_eject(app, type)
          else
            raise Errors::ConfigurationError,
                  "unknown Compose action: #{action || '(missing)'}; expected show, validate, diff or eject"
          end
        end

        def compose_show(compose)
          puts compose.display unless json?
          Result.success(compose.metadata.merge(content: compose.display, fingerprint: compose.fingerprint))
        end

        def compose_validate(type, compose)
          puts "#{type} Compose customization is valid (#{compose.mode})." unless json?
          Result.success(compose.metadata.merge(valid: true, fingerprint: compose.fingerprint))
        end

        def compose_eject(app, type)
          value = Workflows::EjectCompose.new(
            root: options[:root], config: app.config, type: type, config_path: options[:config]
          ).call(force: options[:force])
          puts "Created #{value[:compose_file]} and updated #{value[:config_file]}." unless json?
          Result.success(value)
        end

        def compose_diff(app, type, compose)
          state = app.state_store.read(app.config.environment).dig("resources", "service.#{type}")
          installed = state&.fetch("compose_fingerprint", nil)
          changed = installed != compose.fingerprint
          value = { changed: changed, desired_fingerprint: compose.fingerprint,
                    installed_fingerprint: installed, mode: compose.mode }
          unless json?
            label = if installed
                      changed ? "changed" : "unchanged"
                    else
                      "not installed or from an older state"
                    end
            puts "#{type} Compose: #{label}"
          end
          Result.success(value)
        end

        def destroy_service_data(app, operation, type)
          expected = "#{type}@#{app.config.environment}"
          state = app.state_store.read(app.config.environment).dig("resources", "service.#{type}")
          unless state
            raise Errors::UnsafeOperationError.new(
              "no managed #{type} data exists in #{app.config.environment}",
              hint: "Run `kit service #{type} status`; restore state before attempting data destruction."
            )
          end
          context = { environment: app.config.environment, resource: "service.#{type}",
                      volume: state.fetch("volume", nil), recoverable: false }
          print_destructive_summary(
            environment: context[:environment], provider: app.config.provider.name, resource: context[:resource],
            identifier: context[:volume], recoverable: context[:recoverable]
          )
          backup_path = create_pre_destroy_backup?(type) ? operation.backup : nil
          confirmation = options[:confirm_destroy]
          confirmation ||= ask("Type #{expected} to permanently destroy its data:") unless options[:no_input]
          confirm_exact!(confirmation, expected, "service data destruction", context: context)
          destroyed = with_mutation_lock(app) { operation.destroy_data }
          Result.success({ destroyed: destroyed, backup: backup_path })
        end

        def create_pre_destroy_backup?(type)
          return true if options[:backup_before_destroy]
          return false if options[:no_input] || !$stdin.tty?

          yes?("Create a #{type} data backup on the server before destruction? [y/N]")
        end

        def service_backup(operation)
          path = operation.backup
          puts "Backup created: #{path}" unless json?
          Result.success({ path: path })
        end

        def dispatch_resource_action(app, operation, action)
          case action
          when "list" then dns_list(app)
          when "plan" then build_plan(app, [operation])
          when "apply" then apply_operations(app, [operation])
          when "remove"
            confirm_named_action!("remove DNS", app.config.environment, option: :yes)
            with_mutation_lock(app) { Result.success(operation.rollback) }
          else raise Errors::ConfigurationError, "unknown DNS action: #{action}"
          end
        end

        def dns_list(app)
          values = app.config.dns.domains
          values.each { |domain| puts domain } unless json?
          Result.success(values)
        end

        def dispatch_docker_action(app, operation, action)
          case action
          when "status" then resource_status(app, "docker")
          when "install" then apply_operations(app, [operation])
          when "uninstall"
            active_services = app.state_store.read(app.config.environment)["resources"].keys.grep(/\Aservice\./)
            unless active_services.empty?
              raise Errors::UnsafeOperationError.new(
                "Docker cannot be removed while managed services exist",
                hint: "Remove services first: #{active_services.join(', ')}"
              )
            end
            confirm_named_action!("uninstall Docker", app.config.environment, option: :yes)
            with_mutation_lock(app) { Result.success(operation.rollback) }
          else raise Errors::ConfigurationError, "unknown Docker action: #{action}"
          end
        end

        def inspect_environment(app)
          result = Workflows::InspectEnvironment.new(
            config: app.config,
            provider: app.provider,
            state_store: app.state_store,
            event_bus: app.event_bus
          ).call
          print_environment_status(result.value) unless json?
          result
        end

        def destroy_server(app)
          expected = app.config.server.name
          managed = app.state_store.read(app.config.environment).dig("resources", "server")
          unless managed&.fetch("id", nil)
            raise Errors::UnsafeOperationError.new(
              "no managed server ID exists in state",
              hint: "Restore state or use the verified `kit server import` recovery flow first."
            )
          end
          print_destructive_summary(
            environment: app.config.environment, provider: app.config.provider.name,
            resource: expected, identifier: managed&.fetch("id", nil), recoverable: false
          )
          confirmation = options[:confirm_destroy]
          confirmation ||= ask("Type #{expected} to permanently destroy the server:") unless options[:no_input]
          dns_operation = app.operations.find { |operation| operation.resource == "dns" }
          Workflows::DestroyServer.new(
            config: app.config,
            provider: app.provider,
            state_store: app.state_store,
            dns_operation: dns_operation,
            event_bus: app.event_bus
          ).call(confirmation: confirmation)
        end

        def import_server(app)
          result = Workflows::ImportServer.new(
            config: app.config,
            provider: app.provider,
            state_store: app.state_store,
            event_bus: app.event_bus
          ).call(provider_id: options[:provider_id], confirmation: options[:confirm_import])
          unless json?
            if result.metadata[:unchanged]
              puts "State already tracks provider ID #{result.value}."
            else
              puts "Imported server #{result.value.name} (provider ID #{result.value.id}) " \
                   "into #{app.config.environment}."
              puts "Only the server identity was imported; run `kit doctor` before applying remote resources."
            end
          end
          result
        end

        def open_ssh(app)
          current = app.provider.find_server(name: app.config.server.name, tags: app.config.server.tags)
          raise Errors::ConnectionError, "server has no public IP" unless current&.public_ip

          known_hosts = File.expand_path(".kitsune/known_hosts", options[:root])
          unless app.transport_factory.deploy.reachable?
            raise Errors::ConnectionError, "the deploy SSH connection could not be verified"
          end

          Kernel.exec(
            "ssh", "-i", app.config.ssh.key_path, "-p", app.config.ssh.port.to_s,
            "-o", "StrictHostKeyChecking=yes", "-o", "UserKnownHostsFile=#{known_hosts}",
            "#{app.config.ssh.user}@#{current.public_ip}"
          )
        end

        def confirm_host_key(host:, fingerprint:, key_type:)
          expected = options[:trust_host_key]
          if expected
            return true if expected == fingerprint

            raise Errors::UnsafeOperationError.new(
              "SSH host-key fingerprint does not match --trust-host-key",
              context: { host: host, expected: expected, actual: fingerprint }
            )
          end
          if options[:no_input] || !$stdin.tty? || json?
            raise Errors::UnsafeOperationError.new(
              "SSH host key is not trusted",
              hint: "Verify the provider-console fingerprint, then pass --trust-host-key #{fingerprint}.",
              context: { host: host, fingerprint: fingerprint, key_type: key_type }
            )
          end

          puts "SSH host key for #{host} (#{key_type}): #{fingerprint}"
          yes?("Trust and save this host key? [y/N]")
        end

        def find_service_operation(app, type, action)
          raise Errors::ConfigurationError, "unknown service type: #{type}" unless %w[postgres redis].include?(type)

          service = app.config.services.public_send(type)
          if service.enabled && service.mode == "external"
            return nil if action == "status"

            raise Errors::UnsafeOperationError.new(
              "#{type} is configured as an external service",
              hint: "Manage its lifecycle with its provider; Kitsune Kit only reports the configured endpoint."
            )
          end
          enabled = service.enabled
          return app.service_operation(type) if enabled || action != "install"

          raise Errors::ConfigurationError.new(
            "#{type} is not enabled in configuration",
            hint: "Set services.#{type}.enabled to true and configure its secret."
          )
        end

        def apply_operations(app, operations)
          plan_result = build_plan(app, operations)
          plan = plan_result.value
          return Result.success([], metadata: { unchanged: true }) unless plan.changed?
          return plan_result if options[:dry_run]

          confirm_apply!(plan)
          Workflows::ApplyPlan.new(
            config: app.config,
            operations: operations,
            state_store: app.state_store,
            event_bus: app.event_bus
          ).call(plan: plan)
        end

        def build_plan(app, operations)
          result = Workflows::BuildPlan.new(
            config: app.config,
            operations: operations,
            event_bus: app.event_bus
          ).call
          print_plan(result.value) unless json?
          result
        end

        def service_status(app, type)
          service = app.config.services.public_send(type)
          return resource_status(app, "service.#{type}") unless service.enabled && service.mode == "external"

          value = { mode: "external", host: service.host, port: service.port, managed: false }
          puts("service.#{type}: external (#{service.host}:#{service.port})") unless json?
          Result.success(value)
        end

        def resource_status(app, resource)
          value = app.state_store.read(app.config.environment).dig("resources", resource)
          if json?
            Result.success(value)
          else
            status = if !value
                       "not managed"
                     elsif value["installed"] == false
                       "removed (data preserved)"
                     else
                       "managed"
                     end
            puts("#{resource}: #{status}")
          end
          Result.success(value)
        end

        def confirm_named_action!(action, expected, option:)
          return if options[option]
          if options[:no_input] || !$stdin.tty?
            raise Errors::UnsafeOperationError.new(
              "#{action} requires confirmation",
              hint: "Pass --yes after reviewing the affected environment (#{expected})."
            )
          end
          return if yes?("#{action.capitalize} in #{expected}? [y/N]")

          raise Errors::UnsafeOperationError, "#{action} was not confirmed"
        end

        def confirm_exact!(actual, expected, action, context: {})
          return if actual == expected

          raise Errors::UnsafeOperationError.new(
            "#{action} was not confirmed",
            hint: "Pass --confirm-destroy #{expected} after creating a backup.",
            context: context
          )
        end

        def print_destructive_summary(environment:, provider:, resource:, identifier:, recoverable:)
          return if json?

          puts
          puts "Permanent destruction"
          puts "  Environment: #{environment}"
          puts "  Provider:    #{provider}"
          puts "  Resource:    #{resource}"
          puts "  Identifier:  #{identifier || 'not recorded'}"
          puts "  Recoverable: #{recoverable ? 'yes' : 'no; restore only from an independent backup'}"
          puts
        end

        def with_mutation_lock(app, &)
          app.state_store.with_execution_lock(app.config.environment, &)
        end

        def print_plan(plan)
          puts
          puts "Plan for environment: #{plan.environment}"
          puts
          if options[:quiet]
            puts "#{plan.changed_count} change(s), #{plan.changes.length - plan.changed_count} unchanged"
            return
          end

          plan.changes.each do |change|
            marker = { "create" => "+", "update" => "~", "delete" => "-", "no_change" => "=" }.fetch(change.action)
            puts "  #{marker} #{change.summary}"
          end
          puts
          puts "#{plan.changed_count} change(s), #{plan.changes.length - plan.changed_count} unchanged"
        end

        def print_checks(checks)
          checks.each do |check|
            puts format("%<name>-24s %<status>-5s %<message>s",
                        name: check.name, status: check.status.upcase, message: check.message)
            puts "#{' ' * 31}#{check.hint}" if check.hint
          end
        end

        def print_environment_status(status)
          puts
          puts "Environment: #{status.environment}"
          if status.server
            puts "Server:      #{status.server.name} (#{status.server.status}, #{status.server.public_ip || 'no IP'})"
          else
            puts "Server:      not created"
          end
          puts "Managed resources:"
          if status.managed_resources.empty?
            puts "  none"
          else
            status.managed_resources.each_key { |resource| puts "  - #{resource}" }
          end
        end

        def render_error(error)
          filter = @secret_filter || build_secret_filter
          safe_message = filter.filter(error.message)
          safe_hint = filter.filter(error.hint)
          safe_context = filter.filter(error.context)
          if json?
            warn ::JSON.generate(
              schema_version: 1,
              status: "failure",
              error: { code: error.code, message: safe_message, hint: safe_hint, context: safe_context }
            )
          else
            warn "Error [#{error.code}]: #{safe_message}"
            warn "Hint: #{safe_hint}" if safe_hint
            warn "Context: #{safe_context.inspect}" if options[:debug] && !safe_context.empty?
          end
        end

        def render_unexpected_error(error)
          filter = @secret_filter || build_secret_filter
          safe_message = filter.filter(error.message)
          if json?
            warn ::JSON.generate(
              schema_version: 1,
              status: "failure",
              error: { code: "unexpected_error", message: safe_message }
            )
          else
            warn "Unexpected error: #{safe_message}"
            warn filter.filter(error.full_message) if options[:debug]
          end
        end

        def json? = options[:format] == "json"
      end
    end
  end
end
