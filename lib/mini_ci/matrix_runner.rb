# frozen_string_literal: true

require "thread"

require_relative "buffered_job_output"
require_relative "command_runner"
require_relative "concurrency_config"
require_relative "matrix_expander"
require_relative "matrix_job_result"
require_relative "matrix_run_result"
require_relative "pipeline"
require_relative "reporter"

module MiniCi
  class MatrixRunner
    Job = Struct.new(:index, :combination, :display_name, keyword_init: true)
    CompletedJob = Struct.new(:index, :total, :display_name, :job_result, :output, :error, keyword_init: true)

    def initialize(
      name:,
      name_explicit: true,
      matrix_definition:,
      before_all:,
      steps:,
      after_all:,
      env: {},
      concurrency: ConcurrencyConfig.new(nil),
      command_runner: nil,
      command_runner_factory: nil,
      artifact_collector: nil,
      artifact_store: nil,
      reporter: Reporter.new,
      clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
      sleeper: ->(seconds) { sleep(seconds) },
      expander: MatrixExpander.new
    )
      @name = name
      @name_explicit = name_explicit
      @matrix_definition = matrix_definition
      @before_all = before_all
      @steps = steps
      @after_all = after_all
      @env = env.dup.freeze
      @concurrency = concurrency
      @command_runner = command_runner
      @command_runner_factory = command_runner_factory
      @artifact_collector = artifact_collector
      @artifact_store = artifact_store
      @reporter = reporter
      @clock = clock
      @sleeper = sleeper
      @expander = expander
    end

    def run
      combinations = @expander.expand(@matrix_definition)
      requested_concurrency = requested_concurrency_for(combinations.length)
      actual_worker_count = @concurrency.resolve(job_count: combinations.length)
      started_at = @clock.call
      job_results = Array.new(combinations.length)
      jobs = build_jobs(combinations)
      job_queue = build_job_queue(jobs, actual_worker_count)
      completion_queue = Queue.new
      errors = []

      @reporter.header(@name)
      @reporter.matrix_run_started(
        job_count: combinations.length,
        requested_concurrency: requested_concurrency,
        actual_worker_count: actual_worker_count
      )

      workers = actual_worker_count.times.map do
        Thread.new { worker_loop(job_queue, completion_queue, job_results, combinations.length) }
      end
      workers.each { |worker| worker.report_on_exception = false }

      combinations.length.times do
        completed_job = completion_queue.pop
        errors << completed_job.error if completed_job.error
        @reporter.matrix_job_completed(completed_job)
      end

      workers.each(&:join)
      raise_internal_error(errors.first) unless errors.empty?

      result = MatrixRunResult.new(
        matrix_job_results: job_results,
        total_duration: @clock.call - started_at,
        requested_concurrency: requested_concurrency,
        actual_worker_count: actual_worker_count
      )
      @reporter.matrix_summary(result)
      result
    end

    private

    def build_jobs(combinations)
      combinations.each_with_index.map do |combination, index|
        Job.new(
          index: index,
          combination: combination,
          display_name: display_name_for(combination)
        )
      end
    end

    def build_job_queue(jobs, worker_count)
      Queue.new.tap do |queue|
        jobs.each { |job| queue << job }
        worker_count.times { queue << nil }
      end
    end

    def worker_loop(job_queue, completion_queue, job_results, total_jobs)
      loop do
        job = job_queue.pop
        break unless job

        completed_job = execute_job(job, total_jobs)
        job_results[job.index] = completed_job.job_result if completed_job.job_result
        completion_queue << completed_job
      end
    end

    def execute_job(job, total_jobs)
      buffer = BufferedJobOutput.new
      job_reporter = Reporter.new(output: buffer.io)
      command_runner = command_runner_for(buffer)

      job_reporter.matrix_job_started(index: job.index + 1, total: total_jobs, display_name: job.display_name)

      pipeline_result = Pipeline.new(
        name: job.display_name,
        before_all: @before_all,
        steps: @steps,
        after_all: @after_all,
        env: @env.merge(job.combination.environment),
        command_runner: command_runner,
        reporter: job_reporter,
        artifact_collector: @artifact_collector,
        artifact_store: @artifact_store,
        artifact_job_directory: artifact_job_directory_for(job),
        clock: @clock,
        sleeper: @sleeper,
        announce_header: false
      ).run

      job_result = MatrixJobResult.new(
        combination: job.combination,
        pipeline_result: pipeline_result,
        display_name: job.display_name
      )
      job_reporter.matrix_job_finished(job_result)

      CompletedJob.new(index: job.index, total: total_jobs, display_name: job.display_name, job_result: job_result, output: buffer.string)
    rescue StandardError => e
      CompletedJob.new(index: job.index, total: total_jobs, display_name: job.display_name, output: buffer&.string.to_s, error: e)
    ensure
      buffer&.close
    end

    def command_runner_for(buffer)
      return @command_runner if @command_runner

      if @command_runner_factory
        @command_runner_factory.call(buffer)
      else
        CommandRunner.new(stdout: buffer.io, stderr: buffer.io)
      end
    end

    def artifact_job_directory_for(job)
      return nil unless @artifact_store

      @artifact_store.job_directory(index: job.index + 1, label: job.combination.label)
    end

    def requested_concurrency_for(job_count)
      return @concurrency.value if @concurrency.value

      @concurrency.resolve(job_count: job_count)
    end

    def raise_internal_error(error)
      raise InternalError, "internal error while running matrix job: #{error.class}: #{error.message}"
    end

    def display_name_for(combination)
      return combination.label unless @name_explicit

      "#{@name} [#{combination.label}]"
    end
  end
end
