# frozen_string_literal: true

module MiniCi
  class MatrixCombination
    attr_reader :values

    def initialize(values)
      @values = values.transform_values(&:to_s).freeze
      freeze
    end

    def label
      values.map { |key, value| "#{key}=#{value}" }.join(", ")
    end

    def environment
      values.each_with_object({}) do |(key, value), env|
        env["MATRIX_#{key.upcase}"] = value
      end.freeze
    end
  end
end
