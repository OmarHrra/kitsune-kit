# frozen_string_literal: true

module Kitsune
  module Kit
    module Errors
      class Error < StandardError
        attr_reader :code, :hint, :context, :retryable

        def initialize(message, code:, hint: nil, context: {}, retryable: false)
          super(message)
          @code = code
          @hint = hint
          @context = context.freeze
          @retryable = retryable
        end
      end

      class ConfigurationError < Error
        DEFAULT_HINT = "Review the selected configuration and run `kit doctor`."

        def initialize(message, hint: DEFAULT_HINT, **)
          super(message, code: "configuration_error", hint: hint, **)
        end
      end

      class AuthenticationError < Error
        DEFAULT_HINT = "Check the configured credential variable, scope and provider account."

        def initialize(message, hint: DEFAULT_HINT, **)
          super(message, code: "authentication_error", hint: hint, **)
        end
      end

      class ProviderError < Error
        DEFAULT_HINT = "Check provider status, permissions, quotas and connectivity, then retry."

        def initialize(message, hint: DEFAULT_HINT, **)
          super(message, code: "provider_error", hint: hint, **)
        end
      end

      class ConnectionError < Error
        DEFAULT_HINT = "Verify the server address, SSH key, host fingerprint and firewall route."

        def initialize(message, hint: DEFAULT_HINT, **)
          super(message, code: "connection_error", hint: hint, **)
        end
      end

      class RemoteCommandError < Error
        DEFAULT_HINT = "Inspect the redacted remote error, correct the server condition and resume."

        def initialize(message, hint: DEFAULT_HINT, **)
          super(message, code: "remote_command_error", hint: hint, **)
        end
      end

      class VerificationError < Error
        DEFAULT_HINT = "Do not assume the change succeeded; inspect state and run `kit doctor` before retrying."

        def initialize(message, hint: DEFAULT_HINT, **)
          super(message, code: "verification_error", hint: hint, **)
        end
      end

      class UnsafeOperationError < Error
        DEFAULT_HINT = "Review the exact target and use the documented explicit confirmation option."

        def initialize(message, hint: DEFAULT_HINT, **)
          super(message, code: "unsafe_operation", hint: hint, **)
        end
      end

      class TimeoutError < Error
        DEFAULT_HINT = "Inspect the last confirmed step and retry or resume with an appropriate positive timeout."

        def initialize(message, hint: DEFAULT_HINT, **)
          super(message, code: "timeout", hint: hint, retryable: true, **)
        end
      end

      EXIT_STATUS = {
        "configuration_error" => 3,
        "authentication_error" => 4,
        "provider_error" => 5,
        "connection_error" => 6,
        "remote_command_error" => 7,
        "verification_error" => 8,
        "unsafe_operation" => 9,
        "timeout" => 10
      }.freeze

      def self.exit_status(error)
        EXIT_STATUS.fetch(error.respond_to?(:code) ? error.code : nil, 1)
      end
    end
  end
end
