# frozen_string_literal: true

module MiniCi
  class MatrixRunResult
    attr_reader :matrix_job_results, :total_duration

    def initialize(matrix_job_results:, total_duration:)
      @matrix_job_results = matrix_job_results.freeze
      @total_duration = total_duration
      freeze
    end

    def success?
      matrix_job_results.all?(&:success?)
    end

    def failed?
      !success?
    end

    def job_count
      matrix_job_results.length
    end

    def passed_job_count
      matrix_job_results.count(&:success?)
    end

    def failed_job_count
      matrix_job_results.count(&:failed?)
    end

    def total_attempts
      matrix_job_results.sum { |job| job.pipeline_result.total_attempts }
    end
  end
end
