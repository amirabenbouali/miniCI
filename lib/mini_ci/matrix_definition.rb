# frozen_string_literal: true

module MiniCi
  class MatrixDefinition
    attr_reader :dimensions

    def initialize(dimensions)
      @dimensions = dimensions.transform_values { |values| values.map(&:to_s).freeze }.freeze
      freeze
    end

    def dimension_count
      dimensions.length
    end

    def total_combination_count
      dimensions.values.reduce(1) { |total, values| total * values.length }
    end

    def empty?
      dimensions.empty?
    end
  end
end
