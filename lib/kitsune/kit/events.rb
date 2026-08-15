# frozen_string_literal: true

require "securerandom"
require "time"

module Kitsune
  module Kit
    module Events
      SCHEMA_VERSION = 1

      class Event < Data.define(:id, :type, :time, :run_id, :data)
        def self.build(type, run_id:, time: Time.now.utc, **data)
          new(
            id: SecureRandom.uuid,
            type: type.to_s,
            time: time.iso8601(6),
            run_id: run_id,
            data: data.freeze
          )
        end

        def to_h
          { schema_version: SCHEMA_VERSION, id: id, type: type, time: time, run_id: run_id, data: data }
        end
      end

      class Bus
        def initialize
          @subscribers = []
          @mutex = Mutex.new
        end

        def subscribe(subscriber = nil, &block)
          target = subscriber || block
          raise ArgumentError, "subscriber or block is required" unless target

          @mutex.synchronize { @subscribers << target }
          target
        end

        def publish(event)
          @mutex.synchronize { @subscribers.dup }.each do |subscriber|
            subscriber.respond_to?(:call) ? subscriber.call(event) : subscriber.handle(event)
          end
          event
        end
      end

      class NullBus
        def subscribe(*) = nil
        def publish(event) = event
      end
    end
  end
end
