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
      pid, stream_threads = spawn_process(env, command)
      status = wait_for_process(pid, timeout)
      stream_threads.each(&:join)
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

    def spawn_process(env, command)
      if redirectable?(@stdout) && redirectable?(@stderr)
        return [Process.spawn(env, command, pgroup: true, out: @stdout, err: @stderr), []]
      end

      stdout_reader, stdout_writer = IO.pipe
      stderr_reader, stderr_writer =
        if @stderr.equal?(@stdout)
          [nil, stdout_writer]
        else
          IO.pipe
        end

      pid = Process.spawn(env, command, pgroup: true, out: stdout_writer, err: stderr_writer)
      stdout_writer.close
      stderr_writer.close if stderr_writer && !stderr_writer.closed?

      threads = [copy_stream(stdout_reader, @stdout)]
      threads << copy_stream(stderr_reader, @stderr) if stderr_reader
      [pid, threads]
    end

    def redirectable?(target)
      target.respond_to?(:fileno) && target.fileno
    rescue IOError, NotImplementedError
      false
    end

    def copy_stream(reader, target)
      Thread.new do
        loop do
          target.write(reader.readpartial(4096))
        end
      rescue EOFError
        reader.close
      ensure
        target.flush if target.respond_to?(:flush)
      end
    end

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
