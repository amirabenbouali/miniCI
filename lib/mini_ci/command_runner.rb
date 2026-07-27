# frozen_string_literal: true

require "English"
require_relative "attempt_result"

module MiniCi
  class CommandRunner
    Result = AttemptResult
    TERMINATION_GRACE_SECONDS = 0.5

    def initialize(clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, stdout: $stdout, stderr: $stderr)
      @clock = clock
      @stdout = stdout
      @stderr = stderr
    end

    def run(command, env: {}, timeout: nil, attempt_number: 1)
      started_at = @clock.call
      flush_output
      pid = Process.spawn(env, command, pgroup: true, out: @stdout, err: @stderr)
      status = wait_for_process(pid, timeout)
      flush_output
      finished_at = @clock.call

      AttemptResult.new(
        attempt_number: attempt_number,
        success: !status[:timed_out] && status[:exit_status].zero?,
        exit_status: status[:exit_status],
        duration: finished_at - started_at,
        timed_out: status[:timed_out],
        timeout: timeout
      )
    end

    private

    def flush_output
      @stdout.flush if @stdout.respond_to?(:flush)
      @stderr.flush if @stderr.respond_to?(:flush) && @stderr != @stdout
    end

    def wait_for_process(pid, timeout)
      deadline = timeout.nil? ? nil : @clock.call + timeout

      loop do
        status = Process.waitpid2(pid, Process::WNOHANG)
        return normal_status(status.last) if status

        if deadline && @clock.call >= deadline
          terminate_process_group(pid)
          return { exit_status: nil, timed_out: true }
        end

        sleep 0.01
      end
    end

    def normal_status(status)
      { exit_status: status.exitstatus || 1, timed_out: false }
    end

    def terminate_process_group(pid)
      kill_process_group("TERM", pid)
      wait_for_exit(pid, TERMINATION_GRACE_SECONDS) || begin
        kill_process_group("KILL", pid)
        wait_for_exit(pid, nil)
      end
    end

    def wait_for_exit(pid, grace_seconds)
      deadline = grace_seconds.nil? ? nil : @clock.call + grace_seconds

      loop do
        status = Process.waitpid2(pid, Process::WNOHANG)
        return status if status
        return nil if deadline && @clock.call >= deadline

        sleep 0.01
      end
    rescue Errno::ECHILD
      true
    end

    def kill_process_group(signal, pid)
      Process.kill(signal, -pid)
    rescue Errno::ESRCH
      nil
    end
  end
end
