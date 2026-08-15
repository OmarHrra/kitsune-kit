# frozen_string_literal: true

require "fileutils"
require "json"
require "pathname"
require "tempfile"
require "time"
require_relative "errors"
require_relative "state_stores/store"

module Kitsune
  module Kit
    class StateStore < StateStores::Store
      SCHEMA_VERSION = 1

      def initialize(root: Dir.pwd)
        super()
        @directory = Pathname(root).expand_path.join(".kitsune/state")
      end

      def read(environment)
        path = state_path(environment)
        return empty_state(environment) unless path.file?

        with_lock(environment, shared: true) do
          parsed = JSON.parse(path.read)
          validate!(parsed, environment)
          parsed
        end
      rescue JSON::ParserError => e
        raise Errors::ConfigurationError.new(
          "state file is invalid JSON: #{path}",
          hint: "Restore the state backup or import the environment again.",
          context: { cause: e.message }
        )
      end

      def update(environment)
        with_lock(environment) do
          current = read_without_lock(environment)
          updated = yield(deep_copy(current))
          updated["updated_at"] = Time.now.utc.iso8601(6)
          validate!(updated, environment)
          write_atomically(state_path(environment), JSON.pretty_generate(updated) << "\n")
          deep_copy(updated)
        end
      end

      def write(environment, state)
        update(environment) { state }
      end

      def delete(environment)
        with_lock(environment) do
          next unless state_path(environment).file?

          state_path(environment).delete
          true
        end
      end

      def with_execution_lock(environment)
        FileUtils.mkdir_p(@directory, mode: 0o700)
        path = @directory.join("#{safe_environment(environment)}.operation.lock")
        File.open(path, File::RDWR | File::CREAT, 0o600) do |file|
          locked = file.flock(File::LOCK_EX | File::LOCK_NB)
          unless locked
            raise Errors::UnsafeOperationError.new(
              "another mutating operation is active for #{environment}",
              hint: "Wait for it to finish or stop it safely before retrying."
            )
          end
          yield
        ensure
          file.flock(File::LOCK_UN) if locked
        end
      end

      private

      def empty_state(environment)
        {
          "version" => SCHEMA_VERSION,
          "environment" => environment.to_s,
          "updated_at" => nil,
          "resources" => {},
          "operations" => [],
          "runs" => {}
        }
      end

      def state_path(environment) = @directory.join("#{safe_environment(environment)}.json")
      def lock_path(environment) = @directory.join("#{safe_environment(environment)}.lock")

      def safe_environment(environment)
        value = environment.to_s
        return value if value.match?(/\A[a-zA-Z0-9_-]+\z/)

        raise Errors::ConfigurationError, "environment name has an invalid format"
      end

      def with_lock(environment, shared: false)
        FileUtils.mkdir_p(@directory, mode: 0o700)
        File.open(lock_path(environment), File::RDWR | File::CREAT, 0o600) do |file|
          file.flock(shared ? File::LOCK_SH : File::LOCK_EX)
          yield
        ensure
          file.flock(File::LOCK_UN)
        end
      end

      def read_without_lock(environment)
        path = state_path(environment)
        return empty_state(environment) unless path.file?

        parsed = JSON.parse(path.read)
        validate!(parsed, environment)
        parsed
      rescue JSON::ParserError => e
        raise Errors::ConfigurationError.new("state file is invalid JSON: #{path}", context: { cause: e.message })
      end

      def validate!(state, environment)
        raise Errors::ConfigurationError, "state must be an object" unless state.is_a?(Hash)
        unless state["version"] == SCHEMA_VERSION
          raise Errors::ConfigurationError.new(
            "unsupported state schema version #{state['version'].inspect}; expected #{SCHEMA_VERSION}",
            hint: "Use a compatible Kitsune Kit version; do not edit IDs manually. Preserve this file and its backup."
          )
        end
        raise Errors::ConfigurationError, "state environment mismatch" unless state["environment"] == environment.to_s
        raise Errors::ConfigurationError, "state resources must be an object" unless state["resources"].is_a?(Hash)
        raise Errors::ConfigurationError, "state operations must be an array" unless state["operations"].is_a?(Array)
        raise Errors::ConfigurationError, "state runs must be an object" unless state["runs"].is_a?(Hash)

        state
      end

      def write_atomically(path, content)
        FileUtils.mkdir_p(path.dirname, mode: 0o700)
        backup = Pathname("#{path}.backup")
        if path.file?
          FileUtils.cp(path, backup)
          File.chmod(0o600, backup)
        end
        Tempfile.create([path.basename.to_s, ".tmp"], path.dirname.to_s, mode: 0o600) do |temp|
          temp.write(content)
          temp.flush
          temp.fsync
          File.rename(temp.path, path)
          File.chmod(0o600, path)
        end
      end

      def deep_copy(value) = Marshal.load(Marshal.dump(value))
    end
  end
end
