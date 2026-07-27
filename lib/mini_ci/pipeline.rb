# frozen_string_literal: true

module MiniCi
  class Pipeline
    def initialize(
      name:,
      steps:,
      env: {},
      command_runner: CommandRunner.new,
      reporter: Reporter.new,
      clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
    )
      @name = validate_name(name)
      @steps = validate_steps(steps)
      @env = env.dup.freeze
      @command_runner = command_runner
      @reporter = reporter
      @clock = clock
    end

    def run
      @reporter.header(@name)

      pipeline_started_at = @clock.call
      step_results = []

      @steps.each_with_index do |step, index|
        @reporter.step_started(step, index: index + 1, total: @steps.length)

        command_result = @command_runner.run(step.command, env: @env.merge(step.env))
        step_result = StepResult.new(
          step: step,
          success: command_result.success?,
          exit_status: command_result.exit_status,
          duration: command_result.duration
        )
        step_results << step_result

        if step_result.success?
          @reporter.step_passed(step_result)
        else
          @reporter.step_failed(step_result)
          break
        end
      end

      pipeline_result = PipelineResult.new(
        name: @name,
        configured_step_count: @steps.length,
        step_results: step_results,
        total_duration: @clock.call - pipeline_started_at
      )

      @reporter.summary(pipeline_result)
      pipeline_result
    end

    private

    def validate_name(name)
      unless name.is_a?(String) && !name.strip.empty?
        raise ArgumentError, "Pipeline name must be a non-empty string"
      end

      name
    end

    def validate_steps(steps)
      unless steps.respond_to?(:each)
        raise ArgumentError, "Pipeline steps must be an ordered collection"
      end

      steps.to_a.each do |step|
        unless step.is_a?(Step)
          raise ArgumentError, "Pipeline steps must be MiniCi::Step instances"
        end
      end
    end
  end
end
