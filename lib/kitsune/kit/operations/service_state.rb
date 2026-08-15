# frozen_string_literal: true

module Kitsune
  module Kit
    module Operations
      class ServiceState
        def initialize(state_store:, environment:, resource:)
          @state_store = state_store
          @environment = environment
          @resource = resource
        end

        def current = state_store.read(environment).dig("resources", resource)
        def managed? = !!current&.fetch("managed", false)

        def record_apply(action, attributes)
          update do |state|
            previous = state["resources"][resource]
            state["resources"][resource] = attributes.merge("previous_state" => previous)
            operation(state, action)
          end
        end

        def record_remove
          update do |state|
            state["resources"][resource]["installed"] = false
            operation(state, "remove")
          end
        end

        def record_rollback(previous)
          update do |state|
            prior = previous["previous_state"]
            prior ? state["resources"][resource] = prior : state["resources"].delete(resource)
            operation(state, "rollback")
          end
        end

        def delete(action)
          update do |state|
            state["resources"].delete(resource)
            operation(state, action)
          end
        end

        private

        attr_reader :state_store, :environment, :resource

        def update(&) = state_store.update(environment, &)

        def operation(state, action)
          state["operations"] << { "resource" => resource, "action" => action, "status" => "applied" }
          state
        end
      end
    end
  end
end
