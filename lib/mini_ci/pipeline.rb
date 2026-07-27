# frozen_string_literal: true

module MiniCi
  class Pipeline
    def initialize(
      name:,
      steps:,
      before_all: [],
      after_all: [],
      env: {},
      command_runner: CommandRunner.new,
      reporter: Reporter.new,
      clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
      sleeper: ->(seconds) { sleep(seconds) }
    )
      @name = validate_name(name)
      @before_all = validate_steps(before_all, "before_all hooks")
      @steps = validate_steps(steps)
      @after_all = validate_steps(after_all, "after_all hooks")
      @env = env.dup.freeze
      @command_runner = command_runner
      @reporter = reporter
      @clock = clock
      @sleeper = sleeper
    end

    def run
      @reporter.header(@name)

      pipeline_started_at = @clock.call
      before_all_results = []
      step_results = []
      after_all_results = []

      run_interruptible_phase(
        @before_all,
        category: :before_all,
        heading: "Setup",
        results: before_all_results
      )

      if before_all_results.none?(&:failed?)
        run_interruptible_phase(
          @steps,
          category: :step,
          heading: "Pipeline",
          results: step_results
        )
      end

      run_cleanup_phase(after_all_results)

      pipeline_result = PipelineResult.new(
        name: @name,
        configured_before_all_count: @before_all.length,
        configured_step_count: @steps.length,
        configured_after_all_count: @after_all.length,
        before_all_results: before_all_results,
        step_results: step_results,
        after_all_results: after_all_results,
        total_duration: @clock.call - pipeline_started_at
      )

      @reporter.summary(pipeline_result)
      pipeline_result
    end

    private

    def run_interruptible_phase(items, category:, heading:, results:)
      return if items.empty?

      @reporter.phase_started(heading)

      items.each_with_index do |step, index|
        step_result = execute_item(step, category: category, index: index + 1, total: items.length)
        results << step_result
        break if step_result.failed?
      end
    end

    def run_cleanup_phase(results)
      return if @after_all.empty?

      @reporter.phase_started("Cleanup")

      @after_all.each_with_index do |step, index|
        results << execute_item(step, category: :after_all, index: index + 1, total: @after_all.length)
      end
    end

    def execute_item(step, category:, index:, total:)
      @reporter.step_started(step, index: index, total: total)
      step_result = run_step(step, category: category)

      if step_result.success?
        @reporter.step_passed(step_result) unless step_result.retried?
      else
        @reporter.step_failed(step_result)
      end

      step_result
    end

    def run_step(step, category:)
      started_at = @clock.call
      attempts = []

      step.maximum_attempts.times do |index|
        attempt_number = index + 1
        @reporter.attempt_started(attempt_number, total: step.maximum_attempts) if step.maximum_attempts > 1

        attempt = @command_runner.run(
          step.command,
          env: @env.merge(step.env),
          timeout: step.timeout,
          attempt_number: attempt_number
        )
        attempts << attempt

        if step.maximum_attempts == 1
          break
        elsif attempt.success?
          @reporter.attempt_passed(attempt)
          break
        else
          @reporter.attempt_failed(attempt)
          retry_if_possible(step, attempt_number)
        end
      end

      StepResult.new(
        step: step,
        attempts: attempts,
        duration: @clock.call - started_at,
        category: category
      )
    end

    def retry_if_possible(step, attempt_number)
      return if attempt_number >= step.maximum_attempts

      @reporter.retrying(step.retry_delay)
      @sleeper.call(step.retry_delay)
    end

    def validate_name(name)
      unless name.is_a?(String) && !name.strip.empty?
        raise ArgumentError, "Pipeline name must be a non-empty string"
      end

      name
    end

    def validate_steps(steps, label = "Pipeline steps")
      unless steps.respond_to?(:each)
        raise ArgumentError, "#{label} must be an ordered collection"
      end

      steps.to_a.each do |step|
        unless step.is_a?(Step)
          raise ArgumentError, "#{label} must be MiniCi::Step instances"
        end
      end
    end
  end
end
