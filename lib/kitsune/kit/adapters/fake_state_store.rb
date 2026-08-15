# frozen_string_literal: true

require "time"
require_relative "../errors"
require_relative "../state_stores/store"

module Kitsune
  module Kit
    module Adapters
      class FakeStateStore < StateStores::Store
        SCHEMA_VERSION = 1

        def initialize
          super
          @states = {}
          @mutex = Mutex.new
          @operation_mutexes = Hash.new { |hash, key| hash[key] = Mutex.new }
        end

        def read(environment)
          name = safe_environment(environment)
          @mutex.synchronize { copy(@states.fetch(name) { empty_state(name) }) }
        end

        def update(environment)
          name = safe_environment(environment)
          @mutex.synchronize do
            updated = yield(copy(@states.fetch(name) { empty_state(name) }))
            updated["updated_at"] = Time.now.utc.iso8601(6)
            validate!(updated, name)
            @states[name] = copy(updated)
          end
          read(name)
        end

        def write(environment, state) = update(environment) { state }

        def delete(environment)
          name = safe_environment(environment)
          @mutex.synchronize { @states.delete(name) ? true : nil }
        end

        def with_execution_lock(environment)
          name = safe_environment(environment)
          lock = @mutex.synchronize { @operation_mutexes[name] }
          unless lock.try_lock
            raise Errors::UnsafeOperationError.new(
              "another mutating operation is active for #{name}",
              hint: "Wait for it to finish or stop it safely before retrying."
            )
          end
          yield
        ensure
          lock&.unlock if lock&.owned?
        end

        private

        def empty_state(environment)
          {
            "version" => SCHEMA_VERSION, "environment" => environment, "updated_at" => nil,
            "resources" => {}, "operations" => [], "runs" => {}
          }
        end

        def safe_environment(environment)
          value = environment.to_s
          return value if value.match?(/\A[a-zA-Z0-9_-]+\z/)

          raise Errors::ConfigurationError, "environment name has an invalid format"
        end

        def validate!(state, environment)
          raise Errors::ConfigurationError, "state must be an object" unless state.is_a?(Hash)
          unless state["version"] == SCHEMA_VERSION
            raise Errors::ConfigurationError,
                  "unsupported state schema version #{state['version'].inspect}; expected #{SCHEMA_VERSION}"
          end
          raise Errors::ConfigurationError, "state environment mismatch" unless state["environment"] == environment
          raise Errors::ConfigurationError, "state resources must be an object" unless state["resources"].is_a?(Hash)
          raise Errors::ConfigurationError, "state operations must be an array" unless state["operations"].is_a?(Array)
          raise Errors::ConfigurationError, "state runs must be an object" unless state["runs"].is_a?(Hash)

          state
        end

        def copy(value) = Marshal.load(Marshal.dump(value))
      end
    end
  end
end
