# frozen_string_literal: true

module MiniCi
  class Reporter
    def initialize(output: $stdout)
      @output = output
    end

    def header(name)
      @output.puts "Mini CI — #{name}"
      @output.puts
    end

    def step_started(step, index:, total:)
      @output.puts "[#{index}/#{total}] #{step.name}"
    end

    def phase_started(name)
      @output.puts name
      @output.puts
    end

    def step_passed(step_result)
      @output.puts "✓ Passed in #{format_duration(step_result.final_attempt.duration)}"
      @output.puts
    end

    def step_failed(step_result)
      if step_result.retried?
        @output.puts
        @output.puts "Step failed after #{step_result.attempt_count} attempts."
      elsif step_result.timed_out?
        @output.puts "✗ Timed out after #{format_duration(step_result.timeout)}"
      else
        @output.puts "✗ Failed with exit code #{step_result.exit_status} in #{format_duration(step_result.duration)}"
      end
      @output.puts
    end

    def step_skipped(step_result)
      @output.puts "– Skipped: #{skip_reason_message(step_result.skip_reason)}"
      @output.puts
    end

    def attempt_started(attempt_number, total:)
      @output.puts
      @output.puts "Attempt #{attempt_number}/#{total}"
    end

    def attempt_passed(attempt)
      @output.puts "✓ Passed in #{format_duration(attempt.duration)}"
      @output.puts
    end

    def attempt_failed(attempt)
      if attempt.timed_out?
        @output.puts "✗ Timed out after #{format_duration(attempt.timeout)}"
      else
        @output.puts "✗ Failed with exit code #{attempt.exit_status} in #{format_duration(attempt.duration)}"
      end
    end

    def retrying(delay)
      @output.puts "Retrying in #{format_duration(delay)}..."
    end

    def matrix_job_started(index:, total:, display_name:)
      @output.puts "Matrix job #{index}/#{total}"
      @output.puts display_name
      @output.puts
    end

    def matrix_job_finished(job_result)
      @output.puts "Job status: #{job_result.success? ? "PASSED" : "FAILED"}"
      @output.puts "Duration: #{format_duration(job_result.pipeline_result.total_duration)}"
      @output.puts
    end

    def matrix_run_started(job_count:, requested_concurrency:, actual_worker_count:)
      @output.puts "Matrix jobs: #{job_count}"
      @output.puts "Concurrency: #{actual_worker_count}"
      @output.puts "Requested concurrency: #{requested_concurrency}" if requested_concurrency != actual_worker_count
      @output.puts "Execution: #{actual_worker_count > 1 ? "parallel" : "sequential"}"
      @output.puts
    end

    def matrix_job_completed(completed_job)
      @output.puts "----------------------------------------"
      @output.puts
      @output.puts "Matrix job #{completed_job.index + 1}/#{completed_job.total} completed"
      @output.puts completed_job.display_name

      if completed_job.job_result
        @output.puts "Status: #{completed_job.job_result.success? ? "PASSED" : "FAILED"}"
      else
        @output.puts "Status: INTERNAL ERROR"
      end
      @output.puts
      @output.print completed_job.output
      @output.puts unless completed_job.output.end_with?("\n")
    end

    def summary(pipeline_result)
      @output.puts "Pipeline summary"
      @output.puts
      @output.puts "Status: #{pipeline_result.success? ? "PASSED" : "FAILED"}"
      @output.puts main_steps_summary_line(pipeline_result)
      @output.puts setup_summary_line(pipeline_result) if pipeline_result.configured_before_all_count.positive?
      @output.puts cleanup_summary_line(pipeline_result) if pipeline_result.configured_after_all_count.positive?
      @output.puts "Retried steps: #{pipeline_result.retried_step_count}" if pipeline_result.retried_step_count.positive?
      @output.puts "Attempts: #{pipeline_result.total_attempts}"
      @output.puts "Duration: #{format_duration(pipeline_result.total_duration)}"
      print_failures(pipeline_result)
    end

    def matrix_summary(matrix_run_result)
      @output.puts "Matrix summary"
      @output.puts

      matrix_run_result.matrix_job_results.each_with_index do |job_result, index|
        @output.puts "#{index + 1}. #{job_result.combination.label}"
        @output.puts "   #{job_result.success? ? "PASSED" : "FAILED"} — #{format_duration(job_result.pipeline_result.total_duration)}"
        if job_result.pipeline_result.primary_failure
          @output.puts "   Failure: #{failure_line(job_result.pipeline_result.primary_failure)}"
        end
        @output.puts
      end

      @output.puts "Overall status: #{matrix_run_result.success? ? "PASSED" : "FAILED"}"
      @output.puts "Jobs: #{matrix_run_result.passed_job_count} passed, #{matrix_run_result.failed_job_count} failed, #{matrix_run_result.job_count} total"
      @output.puts "Concurrency: #{matrix_run_result.actual_worker_count}"
      @output.puts "Wall-clock duration: #{format_duration(matrix_run_result.total_duration)}"
      @output.puts "Combined job time: #{format_duration(matrix_run_result.sum_of_job_durations)}"
      @output.puts "Attempts: #{matrix_run_result.total_attempts}"
    end

    private

    def main_steps_summary_line(pipeline_result)
      if pipeline_result.skipped_main_step_count.positive?
        "#{passed_failed_skipped_summary(pipeline_result)}, #{pipeline_result.configured_step_count} configured"
      else
        "#{passed_failed_skipped_summary(pipeline_result)}, #{pipeline_result.configured_step_count} total"
      end
    end

    def passed_failed_skipped_summary(pipeline_result)
      "Main steps: #{pipeline_result.passed_count} passed, #{pipeline_result.failed_count} failed, #{pipeline_result.skipped_count} skipped"
    end

    def setup_summary_line(pipeline_result)
      "Setup hooks: #{pipeline_result.before_all_passed_count} passed, #{pipeline_result.before_all_failed_count} failed, #{pipeline_result.before_all_skipped_count} skipped"
    end

    def cleanup_summary_line(pipeline_result)
      "Cleanup hooks: #{pipeline_result.after_all_passed_count} passed, #{pipeline_result.after_all_failed_count} failed, #{pipeline_result.after_all_skipped_count} skipped"
    end

    def format_duration(seconds)
      format("%.2fs", seconds)
    end

    def print_failures(pipeline_result)
      return unless pipeline_result.primary_failure

      @output.puts
      @output.puts "Primary failure:"
      @output.puts "  #{failure_line(pipeline_result.primary_failure)}"

      cleanup_failures = pipeline_result.cleanup_failures
      return if cleanup_failures.empty?

      @output.puts
      @output.puts "Cleanup failures:"
      cleanup_failures.each do |failure|
        @output.puts "  #{failure_line(failure)}"
      end
    end

    def failure_line(step_result)
      if step_result.timed_out?
        "#{step_result.step.name} timed out after #{format_duration(step_result.timeout)}"
      elsif step_result.retried?
        "#{step_result.step.name} failed after #{step_result.attempt_count} attempts with exit code #{step_result.exit_status}"
      else
        "#{step_result.step.name} failed with exit code #{step_result.exit_status}"
      end
    end

    def skip_reason_message(reason)
      case reason
      when :previous_failure
        "requires previous success"
      when :no_previous_failure
        "requires previous failure"
      when :when_never
        "when is set to never"
      when :if_condition_false
        "condition was false"
      else
        "not selected"
      end
    end
  end
end
