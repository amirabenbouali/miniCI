# frozen_string_literal: true

module MiniCi
  class AttemptResult
    attr_reader :attempt_number, :exit_status, :duration, :timeout, :started_at, :finished_at

    def initialize(attempt_number:, success:, exit_status:, duration:, timed_out: false, timeout: nil, started_at: nil, finished_at: nil)
      @attempt_number = attempt_number
      @success = success
      @exit_status = exit_status
      @duration = duration
      @timed_out = timed_out
      @timeout = timeout
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

    def timed_out?
      @timed_out
    end
  end
end
