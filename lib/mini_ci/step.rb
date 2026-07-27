# frozen_string_literal: true

module MiniCi
  class Step
    VALID_WHEN_POLICIES = [:success, :failure, :always, :never].freeze

    attr_reader :name, :command, :env, :timeout, :retries, :retry_delay, :when_policy, :condition

    def initialize(name:, command:, env: {}, timeout: nil, retries: 0, retry_delay: 0, when_policy: :success, condition: nil, when_policy_explicit: false)
      @name = validate_text(name, "name")
      @command = validate_text(command, "command")
      @env = env.dup.freeze
      @timeout = validate_timeout(timeout)
      @retries = validate_retries(retries)
      @retry_delay = validate_retry_delay(retry_delay)
      @when_policy = validate_when_policy(when_policy)
      @condition = condition
      @when_policy_explicit = when_policy_explicit
      freeze
    end

    def maximum_attempts
      retries + 1
    end

    def run_on_success?
      when_policy == :success
    end

    def run_on_failure?
      when_policy == :failure
    end

    def always?
      when_policy == :always
    end

    def never?
      when_policy == :never
    end

    def conditional?
      !condition.nil?
    end

    def when_policy_explicit?
      @when_policy_explicit
    end

    private

    def validate_text(value, field_name)
      unless value.is_a?(String) && !value.strip.empty?
        raise ArgumentError, "Step #{field_name} must be a non-empty string"
      end

      value
    end

    def validate_timeout(value)
      return nil if value.nil?

      unless value.is_a?(Numeric) && value.finite? && value.positive?
        raise ArgumentError, "Step timeout must be a positive number"
      end

      value
    end

    def validate_retries(value)
      unless value.is_a?(Integer) && !value.is_a?(TrueClass) && !value.is_a?(FalseClass) && value >= 0
        raise ArgumentError, "Step retries must be a non-negative integer"
      end

      value
    end

    def validate_retry_delay(value)
      unless value.is_a?(Numeric) && !value.is_a?(TrueClass) && !value.is_a?(FalseClass) && value.finite? && value >= 0
        raise ArgumentError, "Step retry_delay must be a non-negative number"
      end

      value
    end

    def validate_when_policy(value)
      policy = value.to_sym if value.respond_to?(:to_sym)
      return policy if VALID_WHEN_POLICIES.include?(policy)

      raise ArgumentError, "Step when_policy must be one of success, failure, always, never"
    end
  end
end
