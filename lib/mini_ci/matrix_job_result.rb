# frozen_string_literal: true

module MiniCi
  class MatrixJobResult
    attr_reader :combination, :pipeline_result, :display_name

    def initialize(combination:, pipeline_result:, display_name:)
      @combination = combination
      @pipeline_result = pipeline_result
      @display_name = display_name
      freeze
    end

    def success?
      pipeline_result.success?
    end

    def failed?
      !success?
    end

    def matrix_values
      combination.values
    end
  end
end
