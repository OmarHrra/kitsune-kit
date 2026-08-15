# frozen_string_literal: true

require "json"
require "time"
require_relative "errors"

module Kitsune
  module Kit
    class RunJournal
      RESUMABLE_STATUSES = %w[running failure cancelled].freeze

      def initialize(state_store:, environment:, run_id:, clock: -> { Time.now.utc })
        @state_store = state_store
        @environment = environment
        @run_id = run_id
        @clock = clock
      end

      def start(changes:, resumed_from: nil)
        update_run do |run|
          run.merge!(
            "status" => "running",
            "started_at" => timestamp,
            "finished_at" => nil,
            "resumed_from" => resumed_from,
            "changes" => normalize(changes),
            "steps" => {}
          )
        end
      end

      def record_step(resource, status, error: nil)
        update_run do |run|
          run["steps"] ||= {}
          run["steps"][resource] = {
            "status" => status,
            "error" => error,
            "updated_at" => timestamp
          }
        end
      end

      def finish(status, error: nil)
        update_run do |run|
          run["status"] = status
          run["error"] = error
          run["finished_at"] = timestamp
        end
      end

      def resumable(requested_id = nil)
        runs = state_store.read(environment)["runs"]
        selected_id = requested_id || runs.keys.reverse.find { |id| resumable_status?(runs.fetch(id)) }
        raise no_resumable_run_error unless selected_id

        run = runs[selected_id]
        raise Errors::ConfigurationError, "run not found: #{selected_id}" unless run

        validate_resumable!(selected_id, run)
        [selected_id, run]
      end

      private

      attr_reader :state_store, :environment, :run_id, :clock

      def update_run
        return unless state_store

        state_store.update(environment) do |state|
          run = state["runs"][run_id] ||= {}
          yield(run)
          state
        end
      end

      def validate_resumable!(selected_id, run)
        unless resumable_status?(run)
          raise Errors::ConfigurationError.new(
            "run #{selected_id} cannot be resumed because its status is #{run['status']}",
            hint: "Resume a failed, cancelled, or interrupted run."
          )
        end
        return if run["changes"].is_a?(Array) && run["steps"].is_a?(Hash)

        raise Errors::ConfigurationError, "run #{selected_id} does not contain a resumable plan"
      end

      def resumable_status?(run) = RESUMABLE_STATUSES.include?(run["status"])

      def no_resumable_run_error
        Errors::ConfigurationError.new(
          "there is no run available to resume",
          hint: "Run `kit apply` first or provide the ID of a failed run."
        )
      end

      def timestamp = clock.call.iso8601(6)
      def normalize(value) = JSON.parse(JSON.generate(value))
    end
  end
end
