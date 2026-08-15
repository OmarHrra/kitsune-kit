# frozen_string_literal: true

require "fileutils"
require "json"
require "pathname"
require "rbconfig"
require "securerandom"
require "time"

module Kitsune
  module Kit
    module Workflows
      class SupportBundle
        MAX_LOG_FILES = 5
        MAX_LOG_LINES = 500

        def initialize(root:, config:, state_store:, doctor:, secret_filter: SecretFilter.new,
                       clock: -> { Time.now.utc })
          @root = Pathname(root).expand_path
          @config = config
          @state_store = state_store
          @doctor = doctor
          @secret_filter = secret_filter
          @clock = clock
        end

        def call
          directory = root.join(".kitsune/support")
          FileUtils.mkdir_p(directory, mode: 0o700)
          path = directory.join("#{clock.call.strftime('%Y%m%dT%H%M%S')}-#{SecureRandom.hex(4)}.json")
          path.write(JSON.pretty_generate(secret_filter.filter(payload)) << "\n")
          File.chmod(0o600, path)
          path.to_s
        end

        private

        attr_reader :root, :config, :state_store, :doctor, :secret_filter, :clock

        def payload
          {
            schema_version: 1,
            generated_at: clock.call.iso8601(6),
            kitsune_version: VERSION,
            ruby: { version: RUBY_VERSION, platform: RUBY_PLATFORM, host_os: RbConfig::CONFIG["host_os"] },
            configuration: serialize(config),
            state: state_store.read(config.environment),
            doctor: doctor.call.value.map(&:to_h),
            logs: selected_logs
          }
        end

        def selected_logs
          directory = root.join(".kitsune/logs")
          return [] unless directory.directory?

          directory.glob("*.jsonl").sort_by(&:mtime).last(MAX_LOG_FILES).map do |path|
            { file: path.basename.to_s, events: read_log(path) }
          end
        end

        def read_log(path)
          path.readlines.last(MAX_LOG_LINES).filter_map do |line|
            JSON.parse(line)
          rescue JSON::ParserError
            { "type" => "invalid_log_line", "message" => "A local log line could not be parsed." }
          end
        rescue SystemCallError => e
          [{ "type" => "log_read_error", "message" => e.class.name }]
        end

        def serialize(value)
          return value.members.to_h { |member| [member, serialize(value.public_send(member))] } if value.is_a?(Data)
          return value.to_h { |key, item| [key, serialize(item)] } if value.is_a?(Hash)
          return value.map { |item| serialize(item) } if value.is_a?(Array)

          value
        end
      end
    end
  end
end
