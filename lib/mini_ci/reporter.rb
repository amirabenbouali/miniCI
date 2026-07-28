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
      elsif step_result.cache_failure?
        @output.puts "✗ Cache configuration failed"
      elsif step_result.artifact_failure? && step_result.final_attempt.success?
        @output.puts "✗ Artifact collection failed"
      elsif step_result.timed_out?
        @output.puts "✗ Timed out after #{format_duration(step_result.timeout)}"
      else
        @output.puts "✗ Failed with exit code #{step_result.exit_status} in #{format_duration(step_result.duration)}"
      end
      @output.puts
    end

    def cache_restored(cache_result)
      if cache_result.disabled?
        @output.puts "Cache: disabled"
      elsif cache_result.failed?
        @output.puts "Cache: configuration failed"
        cache_result.errors.each { |error| @output.puts "Cache error: #{error}" }
      elsif cache_result.exact_hit?
        @output.puts "Cache: exact hit for #{cache_result.restore_source_key} (#{cache_result.restored_file_count} files)"
      elsif cache_result.fallback_hit?
        @output.puts "Cache: fallback hit from #{cache_result.restore_source_key} (#{cache_result.restored_file_count} files)"
      elsif cache_result.miss?
        @output.puts "Cache: miss"
      end

      cache_result.warnings.each { |warning| @output.puts "Warning: #{warning}" }
    end

    def cache_saved(cache_result)
      if cache_result.saved?
        @output.puts "Cache: saved #{cache_result.saved_file_count} files as #{cache_result.resolved_key}"
      else
        @output.puts "Cache: not saved"
      end
      cache_result.warnings.each { |warning| @output.puts "Warning: #{warning}" }
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

    def artifacts(step_result)
      artifact_result = step_result.artifact_result
      if artifact_result.failed?
        @output.puts "Artifacts: collection failed"
        @output.puts "Reason: #{artifact_result.errors.first}"
      else
        @output.puts "Artifacts: #{artifact_result.copied_file_count} files collected"
        @output.puts "Location: #{artifact_result.destination}"
        artifact_result.warnings.each do |warning|
          @output.puts "Warning: #{warning}"
        end
      end
      @output.puts
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
      @output.puts "Artifacts: #{pipeline_result.artifact_count} files" if pipeline_result.artifact_run_directory
      @output.puts "Artifact warnings: #{pipeline_result.artifact_warning_count}" if pipeline_result.artifact_warning_count.positive?
      @output.puts "Artifact failures: #{pipeline_result.artifact_failure_count}" if pipeline_result.artifact_failure_count.positive?
      @output.puts "Artifact location: #{pipeline_result.artifact_run_directory}" if pipeline_result.artifact_run_directory
      print_cache_summary(pipeline_result)
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
      if matrix_run_result.artifact_run_directory
        @output.puts "Artifacts: #{matrix_run_result.artifact_count} files across #{matrix_run_result.job_count} jobs"
        @output.puts "Artifact warnings: #{matrix_run_result.artifact_warning_count}" if matrix_run_result.artifact_warning_count.positive?
        @output.puts "Artifact failures: #{matrix_run_result.artifact_failure_count}" if matrix_run_result.artifact_failure_count.positive?
        @output.puts "Artifact location: #{matrix_run_result.artifact_run_directory}"
      end
      if matrix_run_result.cache_configured_count.positive?
        @output.puts "Cache: #{matrix_run_result.cache_hit_count} hits, #{matrix_run_result.cache_miss_count} misses, #{matrix_run_result.cache_save_count} saves"
        @output.puts "Cache warnings: #{matrix_run_result.cache_warning_count}" if matrix_run_result.cache_warning_count.positive?
      end
      @output.puts "Attempts: #{matrix_run_result.total_attempts}"
    end

    private

    def print_cache_summary(pipeline_result)
      return unless pipeline_result.cache_configured_count.positive?

      @output.puts "Cache: #{pipeline_result.cache_hit_count} hits, #{pipeline_result.cache_miss_count} misses, #{pipeline_result.cache_save_count} saves"
      @output.puts "Cache warnings: #{pipeline_result.cache_warning_count}" if pipeline_result.cache_warning_count.positive?
      @output.puts "Cache failures: #{pipeline_result.cache_failure_count}" if pipeline_result.cache_failure_count.positive?
    end

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
      unless cleanup_failures.empty?
        @output.puts
        @output.puts "Cleanup failures:"
        cleanup_failures.each do |failure|
          @output.puts "  #{failure_line(failure)}"
        end
      end

      print_artifact_failures(pipeline_result)
    end

    def print_artifact_failures(pipeline_result)
      failures = pipeline_result.artifact_failures.reject { |failure| failure.equal?(pipeline_result.primary_failure) }
      return if failures.empty?

      @output.puts
      @output.puts "Artifact failures:"
      failures.each do |failure|
        @output.puts "  #{failure_line(failure)}"
      end
    end

    def failure_line(step_result)
      if step_result.cache_failure?
        "Cache for #{step_result.step.name} failed: #{step_result.cache_result.errors.first}"
      elsif step_result.artifact_failure? && step_result.final_attempt.success?
        "Artifact collection for #{step_result.step.name} failed: #{step_result.artifact_result.errors.first}"
      elsif step_result.timed_out?
        "#{step_result.step.name} timed out after #{format_duration(step_result.timeout)}"
      elsif step_result.retried?
        "#{step_result.step.name} failed after #{step_result.attempt_count} attempts with exit code #{step_result.exit_status}"
      else
        line = "#{step_result.step.name} failed with exit code #{step_result.exit_status}"
        if step_result.artifact_failure?
          "#{line}; artifact collection failed: #{step_result.artifact_result.errors.first}"
        else
          line
        end
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
