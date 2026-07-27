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
                :total_duration

    def initialize(
      name:,
      configured_step_count:,
      step_results:,
      total_duration:,
      configured_before_all_count: 0,
      configured_after_all_count: 0,
      before_all_results: [],
      after_all_results: []
    )
      @name = name
      @configured_before_all_count = configured_before_all_count
      @configured_step_count = configured_step_count
      @configured_after_all_count = configured_after_all_count
      @before_all_results = before_all_results.freeze
      @step_results = step_results.freeze
      @after_all_results = after_all_results.freeze
      @total_duration = total_duration
      freeze
    end

    def success?
      all_results.all?(&:success?) &&
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
      step_results.length
    end

    def skipped_count
      skipped_main_step_count
    end

    def failure_result
      primary_failure
    end

    def total_attempts
      all_results.sum(&:attempt_count)
    end

    def retried_step_count
      all_results.count(&:retried?)
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

    def before_all_passed_count
      before_all_results.count(&:success?)
    end

    def before_all_failed_count
      before_all_results.count(&:failed?)
    end

    def after_all_passed_count
      after_all_results.count(&:success?)
    end

    def after_all_failed_count
      after_all_results.count(&:failed?)
    end

    def skipped_main_step_count
      configured_step_count - step_results.length
    end
  end
end
