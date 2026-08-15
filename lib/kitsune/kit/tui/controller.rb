# frozen_string_literal: true

module Kitsune
  module Kit
    module Tui
      class Controller
        CONFIRMATIONS = {
          apply: "Apply the visible plan?",
          resume: "Resume the latest incomplete run?"
        }.freeze
        SCREEN_KEYS = { "p" => %i[plan plan], "d" => %i[doctor doctor] }.freeze
        SIMPLE_KEYS = { "l" => :logs, "?" => :help, "a" => :apply, "r" => :resume }.freeze
        NAVIGATION_KEYS = { "j" => 1, down: 1, "k" => -1, up: -1 }.freeze
        SCROLL_KEYS = { page_up: 5, page_down: -5 }.freeze
        SCREENS = %i[dashboard plan doctor logs help].freeze

        attr_reader :exit_requested

        def initialize(store:, actions:)
          @store = store
          @actions = actions
          @exit_requested = false
          @worker = nil
          @pending_action = nil
        end

        def handle(key)
          return if key.nil?
          return handle_modal(key) if store.snapshot.modal
          return run_screen_action(key) if SCREEN_KEYS.key?(key)
          return handle_simple(SIMPLE_KEYS.fetch(key)) if SIMPLE_KEYS.key?(key)
          return navigate(NAVIGATION_KEYS.fetch(key)) if NAVIGATION_KEYS.key?(key)
          return store.scroll(SCROLL_KEYS.fetch(key)) if SCROLL_KEYS.key?(key)

          case key
          when "q" then request_exit
          when "\u0003" then cancel_or_exit
          when "\t" then cycle_screen
          end
        end

        def busy? = @worker&.alive? || false

        def start = run(:status, screen: :dashboard)

        def wait
          @worker&.join
        end

        private

        attr_reader :store, :actions

        def request_exit
          if busy?
            store.modal(message: "An operation is active. Quit after it finishes?", action: :quit)
          else
            @exit_requested = true
          end
        end

        def cancel_or_exit
          return @exit_requested = true unless busy?

          actions.cancel
          store.handle(
            Events::Event.build("warning_emitted", run_id: "tui", message: "Cancellation requested")
          )
        end

        def move(delta)
          state = store.snapshot
          return if state.resources.empty?

          store.select((state.selected_resource + delta) % state.resources.length)
        end

        def navigate(delta)
          return store.scroll(-delta) if store.snapshot.screen == :logs

          move(delta)
        end

        def cycle_screen
          current = SCREENS.index(store.snapshot.screen) || 0
          store.show(SCREENS[(current + 1) % SCREENS.length])
        end

        def toggle_help
          state = store.snapshot
          store.show(state.screen == :help ? :dashboard : :help)
        end

        def run_screen_action(key)
          action, screen = SCREEN_KEYS.fetch(key)
          run(action, screen: screen)
        end

        def handle_simple(action)
          case action
          when :logs then store.show(:logs)
          when :help then toggle_help
          else confirm(action)
          end
        end

        def confirm(action)
          return busy_notification if busy?

          @pending_action = action
          store.modal(message: CONFIRMATIONS.fetch(action), action: action)
        end

        def handle_modal(key)
          modal = store.snapshot.modal
          if key == "y"
            store.modal(nil)
            return @exit_requested = true if modal[:action] == :quit

            run(modal[:action], screen: modal[:action] == :apply ? :plan : :logs)
          elsif ["n", :escape, "q"].include?(key)
            store.modal(nil)
          end
        end

        def run(action, screen:)
          return busy_notification if busy?

          store.show(screen)
          store.running(true)
          @worker = Thread.new do
            result = actions.public_send(action)
            update_resources(result.value) if action == :status
            store.show(screen, result: result.value)
          rescue StandardError => e
            store.modal(nil)
            store.show(:logs)
            store.handle(
              Events::Event.build("operation_failed", run_id: "tui", resource: action.to_s,
                                                      summary: action.to_s, message: e.message)
            )
          ensure
            store.running(false)
          end
        end

        def update_resources(status)
          resources = status.managed_resources.map do |name, value|
            state = value.is_a?(Hash) && value["managed"] == false ? "drift" : "managed"
            { name: name, status: state }
          end
          resources.unshift(name: "server", status: status.server ? status.server.status : "missing")
          store.resources = resources
        end

        def busy_notification
          store.handle(Events::Event.build("warning_emitted", run_id: "tui", message: "Another operation is active"))
        end
      end
    end
  end
end
