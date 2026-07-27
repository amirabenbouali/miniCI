# frozen_string_literal: true

require_relative "matrix_expander"
require_relative "matrix_job_result"
require_relative "matrix_run_result"

module MiniCi
  class MatrixRunner
    def initialize(
      name:,
      name_explicit: true,
      matrix_definition:,
      before_all:,
      steps:,
      after_all:,
      env: {},
      command_runner: CommandRunner.new,
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
      @command_runner = command_runner
      @reporter = reporter
      @clock = clock
      @sleeper = sleeper
      @expander = expander
    end

    def run
      combinations = @expander.expand(@matrix_definition)
      started_at = @clock.call
      job_results = []

      @reporter.header(@name)

      combinations.each_with_index do |combination, index|
        display_name = display_name_for(combination)
        @reporter.matrix_job_started(index: index + 1, total: combinations.length, display_name: display_name)

        pipeline_result = Pipeline.new(
          name: display_name,
          before_all: @before_all,
          steps: @steps,
          after_all: @after_all,
          env: @env.merge(combination.environment),
          command_runner: @command_runner,
          reporter: @reporter,
          clock: @clock,
          sleeper: @sleeper,
          announce_header: false
        ).run

        job_result = MatrixJobResult.new(
          combination: combination,
          pipeline_result: pipeline_result,
          display_name: display_name
        )
        job_results << job_result
        @reporter.matrix_job_finished(job_result)
      end

      result = MatrixRunResult.new(
        matrix_job_results: job_results,
        total_duration: @clock.call - started_at
      )
      @reporter.matrix_summary(result)
      result
    end

    private

    def display_name_for(combination)
      return combination.label unless @name_explicit

      "#{@name} [#{combination.label}]"
    end
  end
end
