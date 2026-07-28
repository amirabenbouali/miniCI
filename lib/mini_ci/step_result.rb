# frozen_string_literal: true

require_relative "attempt_result"

module MiniCi
  class StepResult
    attr_reader :step, :attempts, :duration, :started_at, :finished_at, :category, :skip_reason, :artifact_result, :cache_result, :plugin_item_result, :plugin_failure

    def initialize(step:, attempts: nil, success: nil, exit_status: nil, duration: nil, timed_out: false, timeout: nil, started_at: nil, finished_at: nil, category: :step, skipped: false, skip_reason: nil, artifact_result: nil, cache_result: nil, plugin_item_result: nil, plugin_failure: nil)
      @step = step
      @skip_reason = skip_reason
      @artifact_result = artifact_result
      @cache_result = cache_result
      @plugin_item_result = plugin_item_result
      @plugin_failure = plugin_failure
      @attempts = if skipped
                    []
                  else
                    (attempts || [
        AttemptResult.new(
          attempt_number: 1,
          success: success,
          exit_status: exit_status,
          duration: duration,
          timed_out: timed_out,
          timeout: timeout
        )
      ])
                  end.dup.freeze
      @duration = duration || attempts_total_duration
      @started_at = started_at
      @finished_at = finished_at
      @category = validate_category(category)
      validate_skip_reason if skipped
      freeze
    end

    def success?
      return false if skipped?

      final_attempt.success? && !artifact_failure? && !cache_failure? && !plugin_failure?
    end

    def failed?
      return false if skipped?

      !success?
    end

    def timed_out?
      return false if skipped?

      final_attempt.timed_out?
    end

    def exit_status
      return nil if skipped?

      final_attempt.exit_status
    end

    def timeout
      return nil if skipped?

      final_attempt.timeout
    end

    def final_attempt
      attempts.last
    end

    def attempt_count
      attempts.length
    end

    def retried?
      attempt_count > 1
    end

    def skipped?
      !skip_reason.nil?
    end

    def executed?
      !skipped?
    end

    def item
      step
    end

    def total_duration
      duration
    end

    def artifacts_collected?
      !artifact_result.nil? && artifact_result.success?
    end

    def artifact_failure?
      !artifact_result.nil? && artifact_result.failed?
    end

    def cache_failure?
      !cache_result.nil? && cache_result.failed?
    end

    def plugin_failure?
      !plugin_failure.nil?
    end

    def cache_configured?
      !cache_result.nil? && cache_result.configured?
    end

    def before_all?
      category == :before_all
    end

    def normal_step?
      category == :step
    end

    def after_all?
      category == :after_all
    end

    private

    def validate_category(category)
      return category if [:before_all, :step, :after_all].include?(category)

      raise ArgumentError, "Step result category must be :before_all, :step, or :after_all"
    end

    def validate_skip_reason
      return if [:previous_failure, :no_previous_failure, :when_never, :if_condition_false].include?(skip_reason)

      raise ArgumentError, "Skipped step result requires a valid skip reason"
    end

    def attempts_total_duration
      attempts.sum(&:duration)
    end
  end
end
