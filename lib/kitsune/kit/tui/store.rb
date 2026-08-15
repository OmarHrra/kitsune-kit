# frozen_string_literal: true

require_relative "state"

module Kitsune
  module Kit
    module Tui
      class Store
        MAX_LOGS = 200

        def initialize(environment:, secret_filter: SecretFilter.new, terminal_size: [100, 30])
          @state = State.initial(environment: environment, terminal_size: terminal_size)
          @secret_filter = secret_filter
          @mutex = Mutex.new
        end

        def snapshot = @mutex.synchronize { @state }

        def handle(event)
          data = @secret_filter.filter(event.data)
          mutate do |state|
            operations = update_operations(state.operations, event.type, data)
            logs = append_log(state.logs, event.type, data)
            state.with(operations: operations, logs: logs, running: running_for(event.type, state.running),
                       notification: notification_for(event.type, data, state.notification))
          end
        end

        def show(screen, result: nil)
          mutate { |state| state.with(screen: screen, result: result, modal: nil, scroll_offset: 0) }
        end

        def resize(width, height) = mutate { |state| state.with(terminal_size: [width, height]) }
        def select(index) = mutate { |state| state.with(selected_resource: index) }
        def modal(value) = mutate { |state| state.with(modal: value) }
        def running(value) = mutate { |state| state.with(running: value) }

        def scroll(delta)
          mutate do |state|
            maximum = [state.logs.length - 1, 0].max
            state.with(scroll_offset: (state.scroll_offset + delta).clamp(0, maximum))
          end
        end

        def resources=(values)
          mutate { |state| state.with(resources: values, selected_resource: 0) }
        end

        private

        def mutate
          @mutex.synchronize { @state = yield(@state) }
        end

        def update_operations(operations, type, data)
          return operations unless type.start_with?("operation_")

          item = {
            resource: data[:resource], summary: data[:summary], status: type.delete_prefix("operation_"),
            duration_ms: data[:duration_ms], message: data[:message], percent: data[:percent]
          }
          operations.reject { |operation| operation[:resource] == item[:resource] } + [item]
        end

        def append_log(logs, type, data)
          message = data[:message] || data[:summary]
          return logs unless message

          (logs + ["#{type}: #{message}"]).last(MAX_LOGS)
        end

        def running_for(type, current)
          return true if type == "run_started"
          return false if type == "run_finished"

          current
        end

        def notification_for(type, data, current)
          return data[:message] if %w[operation_failed warning_emitted].include?(type)
          return "Run finished: #{data[:status]}" if type == "run_finished"

          current
        end
      end
    end
  end
end
