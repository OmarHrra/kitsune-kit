# frozen_string_literal: true

module Kitsune
  module Kit
    class Clock
      def now = Time.now.utc
      def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      def sleep(seconds) = Kernel.sleep(seconds)
    end
  end
end
