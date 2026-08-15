# frozen_string_literal: true

require_relative "transport"

module Kitsune
  module Kit
    module Adapters
      class FakeTransport < Transport
        attr_reader :calls, :uploads

        def initialize(reachable: true, failures: {})
          super()
          @reachable = reachable
          @failures = failures
          @stubs = {}
          @calls = []
          @uploads = {}
        end

        def stub(command, arguments: [], stdout: "", stderr: "", exit_status: 0, duration_ms: 1)
          @stubs[[command, arguments]] = CommandResult.new(
            stdout: stdout,
            stderr: stderr,
            exit_status: exit_status,
            duration_ms: duration_ms
          )
        end

        def reachable?
          @calls << [:reachable, {}]
          raise @failures[:reachable] if @failures[:reachable]

          @reachable
        end

        def execute(command, arguments: [], timeout: 30, stdin: nil)
          @calls << [:execute, { command: command, arguments: arguments, timeout: timeout, stdin: stdin }]
          raise @failures[:execute] if @failures[:execute]

          @stubs.fetch([command, arguments]) do
            status = command == "test" ? 1 : 0
            CommandResult.new(stdout: "", stderr: "", exit_status: status, duration_ms: 1)
          end
        end

        def upload(content:, remote_path:, mode: "0600")
          @calls << [:upload, { remote_path: remote_path, mode: mode }]
          raise @failures[:upload] if @failures[:upload]

          @uploads[remote_path] = { content: content, mode: mode }
          true
        end
      end
    end
  end
end
