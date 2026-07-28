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
      artifact_collector: nil,
      artifact_store: nil,
      artifact_job_directory: nil,
      clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
      sleeper: ->(seconds) { sleep(seconds) },
      announce_header: true
    )
      @name = validate_name(name)
      @before_all = validate_steps(before_all, "before_all hooks")
      @steps = validate_steps(steps)
      @after_all = validate_steps(after_all, "after_all hooks")
      @env = env.dup.freeze
      @command_runner = command_runner
      @reporter = reporter
      @artifact_collector = artifact_collector
      @artifact_store = artifact_store
      @artifact_job_directory = artifact_job_directory
      @clock = clock
      @sleeper = sleeper
      @announce_header = announce_header
    end

    def run
      @reporter.header(@name) if @announce_header

      pipeline_started_at = @clock.call
      before_all_results = []
      step_results = []
      after_all_results = []
      pipeline_failed = false

      pipeline_failed = run_phase(
        @before_all,
        category: :before_all,
        heading: "Setup",
        results: before_all_results,
        pipeline_failed: pipeline_failed
      )

      pipeline_failed = run_phase(
        @steps,
        category: :step,
        heading: "Pipeline",
        results: step_results,
        pipeline_failed: pipeline_failed
      )

      run_phase(
        @after_all,
        category: :after_all,
        heading: "Cleanup",
        results: after_all_results,
        pipeline_failed: pipeline_failed
      )

      pipeline_result = PipelineResult.new(
        name: @name,
        configured_before_all_count: @before_all.length,
        configured_step_count: @steps.length,
        configured_after_all_count: @after_all.length,
        before_all_results: before_all_results,
        step_results: step_results,
        after_all_results: after_all_results,
        total_duration: @clock.call - pipeline_started_at,
        artifact_run_directory: @artifact_store&.run_directory
      )

      @reporter.summary(pipeline_result)
      pipeline_result
    end

    private

    def run_phase(items, category:, heading:, results:, pipeline_failed:)
      return pipeline_failed if items.empty?

      @reporter.phase_started(heading)

      items.each_with_index do |step, index|
        step_result = execute_item(
          step,
          category: category,
          index: index + 1,
          total: items.length,
          pipeline_failed: pipeline_failed
        )
        results << step_result
        pipeline_failed = true if step_result.failed?
      end

      pipeline_failed
    end

    def execute_item(step, category:, index:, total:, pipeline_failed:)
      @reporter.step_started(step, index: index, total: total)
      skip_reason = skip_reason_for(step, category: category, pipeline_failed: pipeline_failed)

      if skip_reason
        step_result = skipped_step_result(step, category: category, skip_reason: skip_reason)
        @reporter.step_skipped(step_result)
        return step_result
      end

      step_result = run_step(step, category: category, index: index)

      if step_result.success?
        @reporter.step_passed(step_result) unless step_result.retried?
      else
        @reporter.step_failed(step_result)
      end
      @reporter.artifacts(step_result) if step_result.artifact_result

      step_result
    end

    def skip_reason_for(step, category:, pipeline_failed:)
      policy = effective_when_policy(step, category)

      case policy
      when :never
        :when_never
      when :success
        :previous_failure if pipeline_failed
      when :failure
        :no_previous_failure unless pipeline_failed
      when :always
        nil
      end || condition_skip_reason(step)
    end

    def condition_skip_reason(step)
      return nil unless step.condition

      effective_environment = condition_environment_for(step)
      return nil if step.condition.evaluate(effective_environment)

      :if_condition_false
    end

    def effective_when_policy(step, category)
      return :always if category == :after_all && !step.when_policy_explicit?

      step.when_policy
    end

    def condition_environment_for(step)
      ENV.to_h.merge(@env).merge(step.env)
    end

    def skipped_step_result(step, category:, skip_reason:)
      StepResult.new(
        step: step,
        skipped: true,
        skip_reason: skip_reason,
        duration: 0,
        category: category
      )
    end

    def run_step(step, category:, index:)
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

      step_result = StepResult.new(
        step: step,
        attempts: attempts,
        duration: @clock.call - started_at,
        category: category
      )
      attach_artifacts(step_result, category: category, index: index)
    end

    def attach_artifacts(step_result, category:, index:)
      return step_result unless should_collect_artifacts?(step_result)

      destination = @artifact_store.item_directory(
        job_directory: @artifact_job_directory,
        phase: category,
        index: index,
        name: step_result.step.name
      )
      artifact_result = @artifact_collector.collect(step_result.step.artifacts, destination: destination)

      StepResult.new(
        step: step_result.step,
        attempts: step_result.attempts,
        duration: step_result.duration,
        category: category,
        artifact_result: artifact_result
      )
    end

    def should_collect_artifacts?(step_result)
      return false unless @artifact_collector && @artifact_store && @artifact_job_directory
      return false unless step_result.step.artifacts

      if step_result.final_attempt.success?
        step_result.step.artifacts.collect_on_success?
      else
        step_result.step.artifacts.collect_on_failure?
      end
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
