# frozen_string_literal: true

require "English"

module MiniCi
  class CommandRunner
    Result = Struct.new(:success?, :exit_status, :duration, keyword_init: true)

    def initialize(clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @clock = clock
    end

    def run(command, env: {})
      started_at = @clock.call
      system(env, command)
      finished_at = @clock.call
      status = $CHILD_STATUS.exitstatus

      Result.new(
        success?: status.zero?,
        exit_status: status,
        duration: finished_at - started_at
      )
    end
  end
end
