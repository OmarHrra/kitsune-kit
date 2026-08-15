# frozen_string_literal: true

module Kitsune
  module Kit
    class Result < Data.define(:status, :value, :warnings, :metadata)
      STATUSES = %i[success failure cancelled].freeze

      def initialize(status:, value: nil, warnings: [], metadata: {})
        raise ArgumentError, "unknown status: #{status}" unless STATUSES.include?(status.to_sym)

        super(
          status: status.to_sym,
          value: value,
          warnings: warnings.freeze,
          metadata: metadata.freeze
        )
      end

      def success? = status == :success
      def failure? = status == :failure
      def cancelled? = status == :cancelled

      def self.success(value = nil, warnings: [], metadata: {})
        new(status: :success, value: value, warnings: warnings, metadata: metadata)
      end
    end
  end
end
