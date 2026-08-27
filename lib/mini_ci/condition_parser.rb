# frozen_string_literal: true

require_relative "condition"

module MiniCi
  class ConditionParser
    ENV_NAME_PATTERN = /\A[A-Za-z_][A-Za-z0-9_]*\z/
    SUPPORTED_FORMAT = 'Supported format: env.VARIABLE == "value" or env.VARIABLE != "value"'
    EXPRESSION_PATTERN = /\Aenv\.([A-Za-z_][A-Za-z0-9_]*)\s*(==|!=)\s*(?:"((?:\\.|[^"\\])*)"|'((?:\\.|[^'\\])*)')\z/

    def parse(expression)
      raise ArgumentError, "if expression must be a string" unless expression.is_a?(String)

      stripped = expression.strip
      raise ArgumentError, "if expression is empty" if stripped.empty?

      match = EXPRESSION_PATTERN.match(stripped)
      raise ArgumentError, "has unsupported if expression. #{SUPPORTED_FORMAT}" unless match

      variable_name = match[1]
      unless variable_name.match?(ENV_NAME_PATTERN)
        raise ArgumentError, "has unsupported if expression. #{SUPPORTED_FORMAT}"
      end

      Condition.new(
        variable_name: variable_name,
        operator: match[2],
        expected_value: unescape(match[3] || match[4]),
        source: stripped
      )
    end

    private

    def unescape(value)
      value.gsub(/\\(["'\\])/, "\\1")
    end
  end
end
