# frozen_string_literal: true

require "net/ssh/verifiers/always"

module Kitsune
  module Kit
    module Adapters
      class ConfirmingHostKeyVerifier < Net::SSH::Verifiers::Always
        def initialize(&confirmation)
          super()
          @confirmation = confirmation || ->(**) { false }
        end

        def verify(arguments)
          super
        rescue Net::SSH::HostKeyUnknown => e
          remember_if_confirmed(e, arguments)
        end

        def verify_signature(&)
          super
        rescue Net::SSH::HostKeyUnknown => e
          remember_if_confirmed(e, e.data)
        end

        private

        def remember_if_confirmed(error, arguments)
          approved = @confirmation.call(
            host: arguments.fetch(:session).host_keys.host,
            fingerprint: arguments.fetch(:fingerprint),
            key_type: arguments.fetch(:key).ssh_type
          )
          raise error unless approved

          error.remember_host!
          true
        end
      end
    end
  end
end
