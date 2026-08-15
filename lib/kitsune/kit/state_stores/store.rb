# frozen_string_literal: true

module Kitsune
  module Kit
    module StateStores
      class Store
        def read(environment) = raise NotImplementedError
        def update(environment) = raise NotImplementedError
        def write(environment, state) = raise NotImplementedError
        def delete(environment) = raise NotImplementedError
        def with_execution_lock(environment) = raise NotImplementedError
      end
    end
  end
end
