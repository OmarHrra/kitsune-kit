# frozen_string_literal: true

require_relative "reporter"

module Kitsune
  module Kit
    module Reporters
      class Human < Reporter
        SYMBOLS = {
          "run_started" => "START",
          "plan_built" => "PLAN",
          "operation_started" => "RUN",
          "operation_progressed" => "PROGRESS",
          "operation_succeeded" => "OK",
          "operation_skipped" => "SKIP",
          "operation_failed" => "FAIL",
          "warning_emitted" => "WARN",
          "run_finished" => "DONE"
        }.freeze

        def initialize(output: $stdout, error: $stderr, color: nil, quiet: false, verbose: false,
                       secret_filter: SecretFilter.new)
          super()
          @output = output
          @error = error
          @color = color.nil? ? output.tty? && !ENV.key?("NO_COLOR") : color
          @secret_filter = secret_filter
          @quiet = quiet
          @verbose = verbose
        end

        def handle(event)
          return if @quiet && !%w[operation_failed warning_emitted run_finished].include?(event.type)

          data = @secret_filter.filter(event.data)
          stream = %w[operation_failed warning_emitted].include?(event.type) ? @error : @output
          message = message_for(event.type, data)
          stream.puts("#{label(event.type)} #{message}") if message
        end

        private

        def label(type)
          value = "[#{SYMBOLS.fetch(type, type.upcase)}]"
          return value unless @color

          code = case type
                 when "operation_succeeded", "run_finished" then 32
                 when "operation_failed" then 31
                 when "warning_emitted" then 33
                 else 36
                 end
          "\e[#{code}m#{value}\e[0m"
        end

        def message_for(type, data)
          method = "message_#{type}"
          send(method, data) if respond_to?(method, true)
        end

        def message_run_started(data) = "#{data[:command]} for #{data[:environment]}"
        def message_plan_built(data) = "#{data[:changed_count]} change(s), #{data[:unchanged_count]} unchanged"

        def message_operation_started(data)
          progress = data[:index] && data[:total] ? "[#{data[:index]}/#{data[:total]}] " : ""
          "#{progress}#{data[:summary]}"
        end

        def message_operation_succeeded(data)
          duration = data[:duration_ms] ? " (#{data[:duration_ms]}ms)" : ""
          "#{data[:summary]}#{duration}"
        end

        def message_operation_progressed(data)
          "#{data[:summary]}: #{data[:percent]}%" if @verbose
        end

        def message_operation_failed(data) = "#{data[:summary]}: #{data[:message]}"

        def message_operation_skipped(data)
          "#{data[:summary]} (#{data[:reason]})" if @verbose
        end

        def message_warning_emitted(data) = data[:message]
        def message_run_finished(data) = "#{data[:status]} in #{data[:duration_ms]}ms"
      end
    end
  end
end
