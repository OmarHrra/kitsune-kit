# frozen_string_literal: true

module Kitsune
  module Kit
    module SecretStores
      class Store
        def fetch(name, required: true) = raise NotImplementedError
        def configured?(name) = raise NotImplementedError
      end
    end
  end
end
