# frozen_string_literal: true

module MiniCi
  class PipelineResult
    attr_reader :name, :configured_step_count, :step_results, :total_duration

    def initialize(name:, configured_step_count:, step_results:, total_duration:)
      @name = name
      @configured_step_count = configured_step_count
      @step_results = step_results.freeze
      @total_duration = total_duration
      freeze
    end

    def success?
      failed_count.zero? && executed_count == configured_step_count
    end

    def failed?
      !success?
    end

    def passed_count
      step_results.count(&:success?)
    end

    def failed_count
      step_results.count(&:failed?)
    end

    def executed_count
      step_results.length
    end

    def skipped_count
      configured_step_count - executed_count
    end
  end
end
