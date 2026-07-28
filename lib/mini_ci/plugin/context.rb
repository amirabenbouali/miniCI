# frozen_string_literal: true

module MiniCi
  module Plugin
    class Context
      def initialize(values = {})
        @values = values.transform_keys(&:to_sym).freeze
      end

      def method_missing(name, *arguments)
        return @values[name] if arguments.empty? && @values.key?(name)

        super
      end

      def respond_to_missing?(name, include_private = false)
        @values.key?(name) || super
      end

      def environment_variable(name)
        configured_environment.fetch(name.to_s, "")
      end

      def new_with(extra_values)
        self.class.new(@values.merge(extra_values.transform_keys(&:to_sym)))
      end

      def section(title:, lines:)
        output = @values[:output]
        return unless output

        output.puts
        output.puts "Plugin: #{title}"
        Array(lines).each { |line| output.puts line.to_s }
      end

      private

      def configured_environment
        @values.fetch(:configured_environment, {})
      end
    end
  end
end
