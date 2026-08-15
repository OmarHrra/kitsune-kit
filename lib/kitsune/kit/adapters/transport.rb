# frozen_string_literal: true

module Kitsune
  module Kit
    module Adapters
      CommandResult = Data.define(:stdout, :stderr, :exit_status, :duration_ms) do
        def success? = exit_status.zero?

        def to_h
          { stdout: stdout, stderr: stderr, exit_status: exit_status, duration_ms: duration_ms }
        end
      end

      class Transport
        def with_session = yield
        def reachable? = raise NotImplementedError
        def execute(command, arguments: [], timeout: 30, stdin: nil) = raise NotImplementedError
        def upload(content:, remote_path:, mode: "0600") = raise NotImplementedError
      end
    end
  end
end
