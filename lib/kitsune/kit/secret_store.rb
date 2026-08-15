# frozen_string_literal: true

require_relative "errors"
require_relative "secret_stores/store"

module Kitsune
  module Kit
    module SecretStores
      class Environment < Store
        def initialize(env: ENV, filter: nil)
          super()
          @env = env
          @filter = filter
        end

        def fetch(name, required: true)
          value = @env.fetch(name.to_s, "")
          if required && value.empty?
            raise Errors::ConfigurationError.new(
              "required secret #{name} is not set",
              hint: "Export #{name} before running this command."
            )
          end
          @filter&.register(value)
          value
        end

        def configured?(name) = !@env.fetch(name.to_s, "").empty?
      end
    end
  end
end
