# frozen_string_literal: true

require_relative "cache_key_resolver"
require_relative "cache_result"
require_relative "plugin"

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
      cache_store: nil,
      cache_enabled: true,
      cache_key_resolver: nil,
      plugin_registry: Plugin.registry,
      plugin_metadata: nil,
      run_id: nil,
      matrix_values: {},
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
      @cache_store = cache_store
      @cache_enabled = cache_enabled
      @cache_key_resolver = cache_key_resolver || CacheKeyResolver.new(workspace: Dir.pwd)
      @plugin_registry = plugin_registry
      @plugin_runner = Plugin::Runner.new(registry: plugin_registry)
      @plugin_metadata = plugin_metadata || Plugin::MetadataBuilder.new
      @run_id = run_id
      @matrix_values = matrix_values.dup.freeze
      @clock = clock
      @sleeper = sleeper
      @announce_header = announce_header
    end

    def run
      @reporter.header(@name) if @announce_header
      before_pipeline_failure = invoke_plugin_callback(:before_pipeline, pipeline_context)

      pipeline_started_at = @clock.call
      before_all_results = []
      step_results = []
      after_all_results = []
      pipeline_failed = !before_pipeline_failure.nil?
      if before_pipeline_failure
        before_all_results << plugin_failure_result(before_pipeline_failure,
                                                    category: :before_all)
      end

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

      after_pipeline_failure = invoke_plugin_callback(:after_pipeline, pipeline_context(result: pipeline_result))
      if after_pipeline_failure
        after_all_results << plugin_failure_result(after_pipeline_failure, category: :after_all)
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
      end

      @reporter.summary(pipeline_result)
      invoke_plugin_callback(:after_report, pipeline_context(result: pipeline_result))
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
        @reporter.plugin_item_output(step_result) if step.plugin_item?
        @reporter.step_passed(step_result) unless step_result.retried?
      else
        @reporter.step_failed(step_result)
        @reporter.plugin_failure(step_result.plugin_failure) if step_result.plugin_failure?
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
      @last_plugin_item_result = nil
      @last_plugin_failure = nil
      @current_category = category
      before_item_failure = invoke_plugin_callback(:before_item, item_context(step, category: category))
      if before_item_failure
        return StepResult.new(
          step: step,
          success: false,
          exit_status: nil,
          duration: @clock.call - started_at,
          category: category,
          plugin_failure: before_item_failure
        )
      end

      cache_result = restore_cache(step)

      if cache_result&.failed?
        step_result = StepResult.new(
          step: step,
          success: false,
          exit_status: nil,
          duration: @clock.call - started_at,
          category: category,
          cache_result: cache_result
        )
        @reporter.cache_restored(cache_result)
        return step_result
      end

      @reporter.cache_restored(cache_result) if cache_result

      step.maximum_attempts.times do |attempt_index|
        attempt_number = attempt_index + 1
        @reporter.attempt_started(attempt_number, total: step.maximum_attempts) if step.maximum_attempts > 1

        attempt = execute_attempt(step, attempt_number)
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
        category: category,
        cache_result: cache_result,
        plugin_item_result: @last_plugin_item_result
      )
      step_result = attach_artifacts(step_result, category: category, index: index)
      step_result = attach_cache_save(step_result)
      attach_after_item_callback(step_result, category: category)
    end

    def execute_attempt(step, attempt_number)
      if step.plugin_item?
        execute_plugin_item(step, attempt_number)
      else
        @command_runner.run(
          step.command,
          env: @env.merge(step.env),
          timeout: step.timeout,
          attempt_number: attempt_number
        )
      end
    end

    def execute_plugin_item(step, attempt_number)
      started_at = @clock.call
      item_type = @plugin_registry.item_type(step.uses)
      context = item_context(step, category: @current_category).new_with(output: reporter_output)
      @last_plugin_item_result = item_type.execute(step.with, context)
      AttemptResult.new(
        attempt_number: attempt_number,
        success: @last_plugin_item_result.success?,
        exit_status: @last_plugin_item_result.success? ? 0 : 1,
        duration: @clock.call - started_at
      )
    rescue StandardError => e
      failure = PluginFailure.new(
        plugin_name: item_type&.plugin&.name || step.uses,
        plugin_version: item_type&.plugin&.version || "unknown",
        event: :execute_item,
        message: e.message,
        exception_class: e.class.name,
        backtrace: e.backtrace
      )
      @last_plugin_item_result = Plugin::ItemResult.new(
        success: false,
        plugin_name: failure.plugin_name,
        item_type: step.uses,
        failure: failure.message
      )
      @last_plugin_failure = failure
      AttemptResult.new(attempt_number: attempt_number, success: false, exit_status: 1,
                        duration: @clock.call - started_at)
    end

    def attach_artifacts(step_result, category:, index:)
      return step_result unless should_collect_artifacts?(step_result)

      destination = @artifact_store.item_directory(
        job_directory: @artifact_job_directory,
        phase: category,
        index: index,
        name: step_result.step.name
      )
      artifact_result = @artifact_collector.collect(
        step_result.step.artifacts,
        destination: destination,
        env: ENV.to_h.merge(@env).merge(step_result.step.env)
      )

      StepResult.new(
        step: step_result.step,
        attempts: step_result.attempts,
        duration: step_result.duration,
        category: category,
        artifact_result: artifact_result,
        cache_result: step_result.cache_result,
        plugin_item_result: step_result.plugin_item_result,
        plugin_failure: step_result.plugin_failure
      )
    end

    def restore_cache(step)
      return nil unless step.cache

      if !@cache_enabled || !@cache_store
        return CacheResult.new(configured: true, disabled: true, restore_status: :disabled)
      end

      resolved_key = resolve_cache_key(step.cache.key, step)
      restore_keys = step.cache.restore_keys.map { |restore_key| resolve_cache_key(restore_key, step) }
      @cache_store.restore(resolved_key: resolved_key, restore_keys: restore_keys)
    rescue ConfigurationError => e
      CacheResult.new(configured: true, restore_status: :error, errors: [e.message])
    end

    def attach_cache_save(step_result)
      return step_result unless step_result.cache_configured?
      return step_result if step_result.cache_result.disabled?
      return step_result if step_result.cache_result.failed?
      return step_result unless should_save_cache?(step_result)

      save_result = @cache_store.save(
        resolved_key: step_result.cache_result.resolved_key,
        paths: step_result.step.cache.paths
      )
      cache_result = step_result.cache_result.merge_save(**save_result)
      @reporter.cache_saved(cache_result)

      StepResult.new(
        step: step_result.step,
        attempts: step_result.attempts,
        duration: step_result.duration,
        category: step_result.category,
        artifact_result: step_result.artifact_result,
        cache_result: cache_result,
        plugin_item_result: step_result.plugin_item_result,
        plugin_failure: step_result.plugin_failure
      )
    end

    def attach_after_item_callback(step_result, category:)
      failure = @last_plugin_failure || invoke_plugin_callback(
        :after_item,
        item_context(step_result.step, category: category, item_result: step_result)
      )
      @last_plugin_failure = nil
      return step_result unless failure

      StepResult.new(
        step: step_result.step,
        attempts: step_result.attempts,
        duration: step_result.duration,
        category: step_result.category,
        artifact_result: step_result.artifact_result,
        cache_result: step_result.cache_result,
        plugin_item_result: step_result.plugin_item_result,
        plugin_failure: failure
      )
    end

    def should_save_cache?(step_result)
      if step_result.final_attempt.success? && !step_result.artifact_failure?
        step_result.step.cache.save_on_success?
      else
        step_result.step.cache.save_on_failure?
      end
    end

    def resolve_cache_key(template, step)
      @cache_key_resolver.resolve(template, env: ENV.to_h.merge(@env).merge(step.env))
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
      raise ArgumentError, "Pipeline name must be a non-empty string" unless name.is_a?(String) && !name.strip.empty?

      name
    end

    def invoke_plugin_callback(event, context)
      @plugin_runner.invoke(event, context)
    end

    def pipeline_context(result: nil)
      Plugin::Context.new(
        pipeline: @name,
        result: result,
        workspace: Dir.pwd,
        run_id: @run_id,
        metadata: @plugin_metadata,
        output: reporter_output,
        matrix_values: @matrix_values
      )
    end

    def item_context(step, category:, item_result: nil)
      Plugin::Context.new(
        item: step,
        item_result: item_result,
        phase: category,
        workspace: Dir.pwd,
        run_id: @run_id,
        metadata: @plugin_metadata,
        output: reporter_output,
        matrix_values: @matrix_values,
        configured_environment: @env.merge(@matrix_values).merge(step.env)
      )
    end

    def plugin_failure_result(failure, category:)
      StepResult.new(
        step: Step.new(name: "Plugin #{failure.plugin_name} #{failure.event}", command: "plugin-callback"),
        success: false,
        exit_status: nil,
        duration: 0,
        category: category,
        plugin_failure: failure
      )
    end

    def reporter_output
      @reporter.output if @reporter.respond_to?(:output)
    end

    def validate_steps(steps, label = "Pipeline steps")
      raise ArgumentError, "#{label} must be an ordered collection" unless steps.respond_to?(:each)

      steps.to_a.each do |step|
        raise ArgumentError, "#{label} must be MiniCi::Step instances" unless step.is_a?(Step)
      end
    end
  end
end
