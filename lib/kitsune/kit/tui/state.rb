# frozen_string_literal: true

module Kitsune
  module Kit
    module Tui
      State = Data.define(
        :screen, :environment, :resources, :selected_resource, :operations, :logs, :modal, :notification,
        :running, :terminal_size, :result, :scroll_offset
      ) do
        def self.initial(environment:, terminal_size: [100, 30])
          new(screen: :dashboard, environment: environment, resources: [], selected_resource: 0, operations: [],
              logs: [], modal: nil, notification: nil, running: false, terminal_size: terminal_size, result: nil,
              scroll_offset: 0)
        end
      end
    end
  end
end
