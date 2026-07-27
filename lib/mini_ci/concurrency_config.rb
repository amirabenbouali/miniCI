# frozen_string_literal: true

require "etc"

require_relative "errors"

module MiniCi
  class ConcurrencyConfig
    MAX_CONCURRENCY = 32

    attr_reader :value

    def initialize(value)
      @value = validate(value)
      freeze
    end

    def resolve(job_count:)
      [@value || default_for(job_count), job_count, MAX_CONCURRENCY].min
    end

    def automatic?
      @value.nil?
    end

    private

    def validate(value)
      return nil if value.nil?

      unless value.is_a?(Integer) && !value.is_a?(TrueClass) && !value.is_a?(FalseClass) && value.positive?
        raise ConfigurationError, "Invalid pipeline configuration: concurrency must be a positive integer"
      end

      if value > MAX_CONCURRENCY
        raise ConfigurationError, "Invalid pipeline configuration: concurrency #{value} exceeds the maximum of #{MAX_CONCURRENCY}"
      end

      value
    end

    def default_for(job_count)
      processor_count = Etc.nprocessors
      [processor_count, job_count, MAX_CONCURRENCY].min
    rescue NotImplementedError
      [2, job_count, MAX_CONCURRENCY].min
    end
  end
end
