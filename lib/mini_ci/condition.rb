# frozen_string_literal: true

module MiniCi
  class Condition
    attr_reader :variable_name, :operator, :expected_value, :source

    def initialize(variable_name:, operator:, expected_value:, source:)
      @variable_name = variable_name
      @operator = operator
      @expected_value = expected_value
      @source = source
      freeze
    end

    def evaluate(environment)
      actual_value = environment.fetch(variable_name, "").to_s

      case operator
      when "=="
        actual_value == expected_value
      when "!="
        actual_value != expected_value
      else
        false
      end
    end
  end
end
