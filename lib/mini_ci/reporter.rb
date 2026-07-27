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

    def summary(pipeline_result)
      @output.puts "Pipeline summary"
      @output.puts
      @output.puts "Status: #{pipeline_result.success? ? "PASSED" : "FAILED"}"
      @output.puts main_steps_summary_line(pipeline_result)
      @output.puts "Skipped main steps: #{pipeline_result.skipped_main_step_count}" if pipeline_result.skipped_main_step_count.positive?
      @output.puts setup_summary_line(pipeline_result) if pipeline_result.configured_before_all_count.positive?
      @output.puts cleanup_summary_line(pipeline_result) if pipeline_result.configured_after_all_count.positive?
      @output.puts "Retried steps: #{pipeline_result.retried_step_count}" if pipeline_result.retried_step_count.positive?
      @output.puts "Attempts: #{pipeline_result.total_attempts}"
      @output.puts "Duration: #{format_duration(pipeline_result.total_duration)}"
      print_failures(pipeline_result)
    end

    private

    def main_steps_summary_line(pipeline_result)
      if pipeline_result.skipped_main_step_count.positive?
        "#{passed_failed_summary(pipeline_result)}, #{pipeline_result.configured_step_count} configured"
      else
        "#{passed_failed_summary(pipeline_result)}, #{pipeline_result.configured_step_count} total"
      end
    end

    def passed_failed_summary(pipeline_result)
      "Steps: #{pipeline_result.passed_count} passed, #{pipeline_result.failed_count} failed"
    end

    def setup_summary_line(pipeline_result)
      "Setup hooks: #{pipeline_result.before_all_passed_count} passed, #{pipeline_result.before_all_failed_count} failed"
    end

    def cleanup_summary_line(pipeline_result)
      "Cleanup hooks: #{pipeline_result.after_all_passed_count} passed, #{pipeline_result.after_all_failed_count} failed"
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
  end
end
