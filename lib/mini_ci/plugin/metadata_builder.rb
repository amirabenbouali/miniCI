# frozen_string_literal: true

require "json"

module MiniCi
  module Plugin
    class MetadataBuilder
      MAX_BYTES = 1024 * 1024

      def initialize
        @data = {}
      end

      def [](key)
        @data[key.to_s]
      end

      def []=(key, value)
        @data[key.to_s] = validate_value(value)
        validate_size!
      end

      def to_h
        deep_copy(@data).freeze
      end

      private

      def validate_value(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, child), output|
            unless key.is_a?(String)
              raise PluginError, "plugin metadata keys must be strings"
            end

            output[key] = validate_value(child)
          end
        when Array
          value.map { |child| validate_value(child) }
        when String, Integer, Float, TrueClass, FalseClass, NilClass
          value
        else
          raise PluginError, "plugin metadata must be JSON-compatible"
        end
      end

      def validate_size!
        bytes = JSON.generate(@data).bytesize
        return if bytes <= MAX_BYTES

        raise PluginError, "plugin metadata exceeds #{MAX_BYTES} bytes"
      end

      def deep_copy(value)
        JSON.parse(JSON.generate(value))
      end
    end
  end
end

