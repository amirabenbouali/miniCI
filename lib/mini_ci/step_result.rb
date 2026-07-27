# frozen_string_literal: true

require_relative "attempt_result"

module MiniCi
  class StepResult
    attr_reader :step, :attempts, :duration, :started_at, :finished_at, :category

    def initialize(step:, attempts: nil, success: nil, exit_status: nil, duration: nil, timed_out: false, timeout: nil, started_at: nil, finished_at: nil, category: :step)
      @step = step
      @attempts = (attempts || [
        AttemptResult.new(
          attempt_number: 1,
          success: success,
          exit_status: exit_status,
          duration: duration,
          timed_out: timed_out,
          timeout: timeout
        )
      ]).dup.freeze
      @duration = duration || attempts_total_duration
      @started_at = started_at
      @finished_at = finished_at
      @category = validate_category(category)
      freeze
    end

    def success?
      final_attempt.success?
    end

    def failed?
      !success?
    end

    def timed_out?
      final_attempt.timed_out?
    end

    def exit_status
      final_attempt.exit_status
    end

    def timeout
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

    def total_duration
      duration
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

    def attempts_total_duration
      attempts.sum(&:duration)
    end
  end
end
