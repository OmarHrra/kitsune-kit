# frozen_string_literal: true

module Kitsune
  module Kit
    module Tui
      class Application
        def initialize(store:, controller:, renderer: Renderer.new, terminal: Terminal.new)
          @store = store
          @controller = controller
          @renderer = renderer
          @terminal = terminal
        end

        def call
          terminal.run do
            controller.start
            until controller.exit_requested
              width, height = terminal.size
              store.resize(width, height)
              terminal.draw(renderer.render(store.snapshot))
              controller.handle(terminal.read_key)
            end
          end
          0
        ensure
          controller.wait
        end

        private

        attr_reader :store, :controller, :renderer, :terminal
      end
    end
  end
end
