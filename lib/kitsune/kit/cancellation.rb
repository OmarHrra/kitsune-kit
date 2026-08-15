# frozen_string_literal: true

module Kitsune
  module Kit
    class Cancellation
      class Cancelled < StandardError; end

      def initialize
        @cancelled = false
        @mutex = Mutex.new
      end

      def cancel! = @mutex.synchronize { @cancelled = true }
      def cancelled? = @mutex.synchronize { @cancelled }

      def check!
        raise Cancelled, "operation cancelled" if cancelled?
      end
    end
  end
end
