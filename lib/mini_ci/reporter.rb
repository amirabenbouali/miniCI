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

    def step_passed(step_result)
      @output.puts "✓ Passed in #{format_duration(step_result.duration)}"
      @output.puts
    end

    def step_failed(step_result)
      @output.puts "✗ Failed with exit code #{step_result.exit_status} in #{format_duration(step_result.duration)}"
      @output.puts
    end

    def summary(pipeline_result)
      @output.puts "Pipeline summary"
      @output.puts
      @output.puts "Status: #{pipeline_result.success? ? "PASSED" : "FAILED"}"
      @output.puts steps_summary_line(pipeline_result)
      @output.puts "Skipped: #{pipeline_result.skipped_count}" if pipeline_result.skipped_count.positive?
      @output.puts "Duration: #{format_duration(pipeline_result.total_duration)}"
    end

    private

    def steps_summary_line(pipeline_result)
      if pipeline_result.skipped_count.positive?
        "#{passed_failed_summary(pipeline_result)}, #{pipeline_result.configured_step_count} configured"
      else
        "#{passed_failed_summary(pipeline_result)}, #{pipeline_result.configured_step_count} total"
      end
    end

    def passed_failed_summary(pipeline_result)
      "Steps: #{pipeline_result.passed_count} passed, #{pipeline_result.failed_count} failed"
    end

    def format_duration(seconds)
      format("%.2fs", seconds)
    end
  end
end
