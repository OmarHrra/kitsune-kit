# frozen_string_literal: true

module Kitsune
  module Kit
    class Change < Data.define(:resource, :action, :summary, :details, :destructive)
      ACTIONS = %w[create update delete no_change].freeze

      def initialize(resource:, action:, summary:, details: {}, destructive: false)
        raise ArgumentError, "unknown action: #{action}" unless ACTIONS.include?(action.to_s)

        super(
          resource: resource.to_s,
          action: action.to_s,
          summary: summary.to_s,
          details: details.freeze,
          destructive: !!destructive
        )
      end

      def changed? = action != "no_change"
      def destructive? = destructive

      def to_h
        {
          resource: resource,
          action: action,
          summary: summary,
          details: details,
          destructive: destructive
        }
      end

      def self.from_h(value)
        new(
          resource: value.fetch("resource"),
          action: value.fetch("action"),
          summary: value.fetch("summary"),
          details: value.fetch("details", {}),
          destructive: value.fetch("destructive", false)
        )
      end
    end

    class Plan < Data.define(:environment, :changes)
      def initialize(environment:, changes:)
        super(environment: environment.to_s, changes: changes.freeze)
      end

      def changed? = changes.any?(&:changed?)
      def destructive? = changes.any?(&:destructive)
      def changed_count = changes.count(&:changed?)

      def counts
        changes.each_with_object(Hash.new(0)) { |change, total| total[change.action] += 1 }
      end

      def to_h
        {
          environment: environment,
          changed: changed?,
          destructive: destructive?,
          counts: counts,
          changes: changes.map(&:to_h)
        }
      end

      def self.from_h(environment:, changes:)
        new(environment: environment, changes: changes.map { |change| Change.from_h(change) })
      end
    end
  end
end
