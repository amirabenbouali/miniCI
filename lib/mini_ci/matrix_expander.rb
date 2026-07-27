# frozen_string_literal: true

require_relative "matrix_combination"

module MiniCi
  class MatrixExpander
    MAX_JOBS = 256

    def initialize(max_jobs: MAX_JOBS)
      @max_jobs = max_jobs
    end

    def expand(definition)
      raise ArgumentError, "Matrix must contain at least one dimension" if definition.empty?

      count = definition.total_combination_count
      if count > @max_jobs
        raise ArgumentError, "matrix expands to #{count} jobs, exceeding the limit of #{@max_jobs}"
      end

      combinations_for(definition.dimensions.to_a)
    end

    private

    def combinations_for(dimensions)
      dimensions.reduce([{}]) do |combinations, (key, values)|
        combinations.flat_map do |combination|
          values.map { |value| combination.merge(key => value) }
        end
      end.map { |values| MatrixCombination.new(values) }
    end
  end
end
