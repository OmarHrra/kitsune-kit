require "dotenv"

module Kitsune
  module Kit
    class EnvLoader
      @loaded = false

      def self.load!
        return if @loaded

        env = ENV["KIT_ENV"] || read_kit_env || "development"

        possible_paths = [
          ".kitsune/infra.#{env}.env",
          ".kitsune/infra.env"
        ]

        found = possible_paths.find { |path| File.exist?(path) }

        if found
          Dotenv.load(found)
          puts "🧪 Loaded Kitsune environment from #{found}"
        else
          puts "⚠️  No Kitsune infra config found for environment '#{env}' (looked for infra.#{env}.env and infra.env)"
        end

        @loaded = true
      end

      def self.read_kit_env
        path = ".kitsune/kit.env"
        if File.exist?(path)
          vars = Dotenv.parse(path)
          vars["KIT_ENV"]
        else
          nil
        end
      end
    end
  end
end
