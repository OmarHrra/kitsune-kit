# frozen_string_literal: true

require "uri"

module Kitsune
  module Kit
    class SecretFilter
      REDACTED = "[REDACTED]"
      SENSITIVE_KEY = /(token|secret|password|private_key|authorization)/i
      PRIVATE_KEY_BLOCK = /-----BEGIN [^-\r\n]*PRIVATE KEY-----.*?-----END [^-\r\n]*PRIVATE KEY-----/m

      def initialize(values = [])
        @values = []
        values.each { |value| register(value) }
      end

      def register(value)
        string = value.to_s
        @values << string unless string.empty? || @values.include?(string)
        self
      end

      def filter(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, item), result|
            result[key] = key.to_s.match?(SENSITIVE_KEY) ? REDACTED : filter(item)
          end
        when Array
          value.map { |item| filter(item) }
        when String
          filter_string(value)
        else
          value
        end
      end

      private

      def filter_string(value)
        filtered = @values.sort_by { |secret| -secret.length }.reduce(value.dup) do |text, secret|
          text.gsub(secret, REDACTED)
        end
        redact_private_key(redact_uri_password(filtered))
      end

      def redact_uri_password(value)
        value.gsub(%r{([a-z][a-z0-9+.-]*://[^:/@\s]+):[^@\s/]*@}i, "\\1:#{REDACTED}@")
      end

      def redact_private_key(value) = value.gsub(PRIVATE_KEY_BLOCK, REDACTED)
    end
  end
end
