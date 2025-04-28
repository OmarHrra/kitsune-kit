module Kitsune
  module Kit
    class OptionsBuilder
      def self.build(current_options, required: [], defaults: {})
        current = current_options.transform_keys(&:to_sym)

        filled = defaults.dup

        defaults.keys.each do |key|
          env_key = key.to_s.upcase
          filled[key] = ENV[env_key] if ENV[env_key]
        end

        filled.merge!(current)

        missing = required.select { |key| filled[key].nil? }

        unless missing.empty?
          abort "❌ Missing required options: #{missing.join(', ')}"
        end

        filled
      end
    end
  end
end
