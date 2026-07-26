# frozen_string_literal: true

module MiniCi
  class StepResult
    attr_reader :step, :exit_status, :duration, :started_at, :finished_at

    def initialize(step:, success:, exit_status:, duration:, started_at: nil, finished_at: nil)
      @step = step
      @success = success
      @exit_status = exit_status
      @duration = duration
      @started_at = started_at
      @finished_at = finished_at
      freeze
    end

    def success?
      @success
    end

    def failed?
      !success?
    end
  end
end
