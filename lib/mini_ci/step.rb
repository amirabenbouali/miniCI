# frozen_string_literal: true

module MiniCi
  class Step
    attr_reader :name, :command, :env, :timeout

    def initialize(name:, command:, env: {}, timeout: nil)
      @name = validate_text(name, "name")
      @command = validate_text(command, "command")
      @env = env.dup.freeze
      @timeout = validate_timeout(timeout)
    end

    private

    def validate_text(value, field_name)
      unless value.is_a?(String) && !value.strip.empty?
        raise ArgumentError, "Step #{field_name} must be a non-empty string"
      end

      value
    end

    def validate_timeout(value)
      return nil if value.nil?

      unless value.is_a?(Numeric) && value.finite? && value.positive?
        raise ArgumentError, "Step timeout must be a positive number"
      end

      value
    end
  end
end
