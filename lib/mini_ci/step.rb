# frozen_string_literal: true

module MiniCi
  class Step
    attr_reader :name, :command, :env

    def initialize(name:, command:, env: {})
      @name = validate_text(name, "name")
      @command = validate_text(command, "command")
      @env = env.dup.freeze
    end

    private

    def validate_text(value, field_name)
      unless value.is_a?(String) && !value.strip.empty?
        raise ArgumentError, "Step #{field_name} must be a non-empty string"
      end

      value
    end
  end
end
