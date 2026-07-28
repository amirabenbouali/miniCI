# frozen_string_literal: true

module MiniCi
  class PipelineResult
    attr_reader :name,
                :configured_before_all_count,
                :configured_step_count,
                :configured_after_all_count,
                :before_all_results,
                :step_results,
                :after_all_results,
                :total_duration,
                :artifact_run_directory

    def initialize(
      name:,
      configured_step_count:,
      step_results:,
      total_duration:,
      configured_before_all_count: 0,
      configured_after_all_count: 0,
      before_all_results: [],
      after_all_results: [],
      artifact_run_directory: nil
    )
      @name = name
      @configured_before_all_count = configured_before_all_count
      @configured_step_count = configured_step_count
      @configured_after_all_count = configured_after_all_count
      @before_all_results = before_all_results.freeze
      @step_results = step_results.freeze
      @after_all_results = after_all_results.freeze
      @total_duration = total_duration
      @artifact_run_directory = artifact_run_directory
      freeze
    end

    def success?
      all_results.none?(&:failed?) &&
        before_all_results.length == configured_before_all_count &&
        step_results.length == configured_step_count &&
        after_all_results.length == configured_after_all_count
    end

    def failed?
      !success?
    end

    def passed_count
      step_results.count(&:success?)
    end

    def failed_count
      step_results.count(&:failed?)
    end

    def executed_count
      step_results.count(&:executed?)
    end

    def skipped_count
      step_results.count(&:skipped?)
    end

    def failure_result
      primary_failure
    end

    def total_attempts
      all_results.sum(&:attempt_count)
    end

    def retried_step_count
      all_results.count { |result| result.executed? && result.retried? }
    end

    def all_results
      before_all_results + step_results + after_all_results
    end

    def primary_failure
      before_all_results.find(&:failed?) ||
        step_results.find(&:failed?) ||
        cleanup_failures.first
    end

    def cleanup_failures
      after_all_results.select(&:failed?)
    end

    def cleanup_failure_count
      cleanup_failures.length
    end

    def artifact_count
      all_results.sum { |result| result.artifact_result&.copied_file_count || 0 }
    end

    def artifact_warning_count
      all_results.sum { |result| result.artifact_result&.warning_count || 0 }
    end

    def artifact_failure_count
      all_results.sum { |result| result.artifact_result&.error_count || 0 }
    end

    def artifact_failures
      all_results.select(&:artifact_failure?)
    end

    def cache_configured_count
      all_results.count(&:cache_configured?)
    end

    def cache_exact_hit_count
      all_results.count { |result| result.cache_result&.exact_hit? }
    end

    def cache_fallback_hit_count
      all_results.count { |result| result.cache_result&.fallback_hit? }
    end

    def cache_hit_count
      cache_exact_hit_count + cache_fallback_hit_count
    end

    def cache_miss_count
      all_results.count { |result| result.cache_result&.miss? }
    end

    def cache_save_count
      all_results.count { |result| result.cache_result&.saved? }
    end

    def cache_warning_count
      all_results.sum { |result| result.cache_result&.warnings&.length || 0 }
    end

    def cache_failure_count
      all_results.count(&:cache_failure?)
    end

    def cache_failures
      all_results.select(&:cache_failure?)
    end

    def before_all_passed_count
      before_all_results.count(&:success?)
    end

    def before_all_failed_count
      before_all_results.count(&:failed?)
    end

    def before_all_skipped_count
      before_all_results.count(&:skipped?)
    end

    def after_all_passed_count
      after_all_results.count(&:success?)
    end

    def after_all_failed_count
      after_all_results.count(&:failed?)
    end

    def after_all_skipped_count
      after_all_results.count(&:skipped?)
    end

    def skipped_main_step_count
      step_results.count(&:skipped?)
    end

    def passed_failed_skipped_count
      [passed_count, failed_count, skipped_count]
    end
  end
end
