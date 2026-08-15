# frozen_string_literal: true

require "fileutils"
require "json"
require "pathname"

module Kitsune
  module Kit
    class RunLogger
      MAX_FILES = 20

      attr_reader :path

      def initialize(root:, run_id:, secret_filter: SecretFilter.new, clock: Clock.new)
        directory = Pathname(root).expand_path.join(".kitsune/logs")
        FileUtils.mkdir_p(directory, mode: 0o700)
        @path = directory.join("#{clock.now.strftime('%Y%m%dT%H%M%S')}-#{run_id}.jsonl")
        @secret_filter = secret_filter
        FileUtils.touch(@path)
        File.chmod(0o600, @path)
        rotate(directory)
      end

      def handle(event)
        File.open(path, "a", 0o600) do |file|
          file.puts(JSON.generate(@secret_filter.filter(event.to_h)))
        end
      end

      private

      def rotate(directory)
        directory.glob("*.jsonl").sort_by(&:mtime).reverse.drop(MAX_FILES).each(&:delete)
      end
    end
  end
end
