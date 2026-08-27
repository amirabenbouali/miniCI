# frozen_string_literal: true

module MiniCi
  class MatrixRunResult
    attr_reader :matrix_job_results, :total_duration, :requested_concurrency, :actual_worker_count

    def initialize(matrix_job_results:, total_duration:, requested_concurrency: 1, actual_worker_count: 1)
      @matrix_job_results = matrix_job_results.freeze
      @total_duration = total_duration
      @requested_concurrency = requested_concurrency
      @actual_worker_count = actual_worker_count
      freeze
    end

    def success?
      matrix_job_results.all?(&:success?)
    end

    def failed?
      !success?
    end

    def status
      success? ? "passed" : "failed"
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

    def artifact_run_directory
      matrix_job_results.find do |job|
        job.pipeline_result.artifact_run_directory
      end&.pipeline_result&.artifact_run_directory
    end

    def artifact_count
      matrix_job_results.sum { |job| job.pipeline_result.artifact_count }
    end

    def artifact_warning_count
      matrix_job_results.sum { |job| job.pipeline_result.artifact_warning_count }
    end

    def artifact_failure_count
      matrix_job_results.sum { |job| job.pipeline_result.artifact_failure_count }
    end

    def cache_configured_count
      matrix_job_results.sum { |job| job.pipeline_result.cache_configured_count }
    end

    def cache_hit_count
      matrix_job_results.sum { |job| job.pipeline_result.cache_hit_count }
    end

    def cache_exact_hit_count
      matrix_job_results.sum { |job| job.pipeline_result.cache_exact_hit_count }
    end

    def cache_fallback_hit_count
      matrix_job_results.sum { |job| job.pipeline_result.cache_fallback_hit_count }
    end

    def cache_miss_count
      matrix_job_results.sum { |job| job.pipeline_result.cache_miss_count }
    end

    def cache_save_count
      matrix_job_results.sum { |job| job.pipeline_result.cache_save_count }
    end

    def cache_warning_count
      matrix_job_results.sum { |job| job.pipeline_result.cache_warning_count }
    end

    def plugin_failures
      matrix_job_results.flat_map { |job| job.pipeline_result.plugin_failures }.freeze
    end

    def plugin_failure_count
      plugin_failures.length
    end

    def parallel?
      actual_worker_count > 1
    end

    def sum_of_job_durations
      matrix_job_results.sum { |job| job.pipeline_result.total_duration }
    end
  end
end
