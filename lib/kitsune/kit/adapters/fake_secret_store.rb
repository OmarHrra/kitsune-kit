# frozen_string_literal: true

require_relative "../errors"
require_relative "../secret_stores/store"

module Kitsune
  module Kit
    module Adapters
      class FakeSecretStore < SecretStores::Store
        attr_reader :fetches

        def initialize(values = {})
          super()
          @values = values.transform_keys(&:to_s)
          @fetches = []
        end

        def fetch(name, required: true)
          key = name.to_s
          @fetches << key
          value = @values.fetch(key, "")
          if required && value.empty?
            raise Errors::ConfigurationError.new(
              "required secret #{key} is not set", hint: "Provide #{key} through the configured secret store."
            )
          end
          value
        end

        def configured?(name) = !@values.fetch(name.to_s, "").empty?
        def set(name, value) = @values[name.to_s] = value.to_s
      end
    end
  end
end
