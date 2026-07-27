# frozen_string_literal: true

require "yaml"

require_relative "condition_parser"

module MiniCi
  class ConfigLoader
    DEFAULT_CONFIG_FILE = "pipeline.yml"
    DEFAULT_PIPELINE_NAME = "Mini CI"
    ENV_NAME_PATTERN = /\A[A-Za-z_][A-Za-z0-9_]*\z/
    VALID_WHEN_POLICIES = ["success", "failure", "always", "never"].freeze

    Configuration = Struct.new(:name, :before_all, :steps, :after_all, :env, keyword_init: true)

    def initialize(path: DEFAULT_CONFIG_FILE)
      @path = path
    end

    def load
      file_path = locate_file
      data = parse_yaml(file_path)
      validate_and_build(data)
    end

    private

    def locate_file
      expanded = File.expand_path(@path)

      unless File.file?(expanded)
        raise FileNotFoundError, "#{@path} was not found"
      end

      expanded
    end

    def parse_yaml(file_path)
      content = File.read(file_path)
      YAML.safe_load(content, aliases: false)
    rescue Psych::SyntaxError, Psych::AliasesNotEnabled, Psych::DisallowedClass => e
      raise ConfigurationError, "Invalid YAML in #{File.basename(file_path)}: #{e.message}"
    end

    def validate_and_build(data)
      unless data.is_a?(Hash)
        raise ConfigurationError, "Invalid pipeline configuration: expected a mapping at the top level"
      end

      pipeline_name = extract_pipeline_name(data)
      env = build_env(data.fetch("env", nil), "global env")
      before_all = build_hooks(data.fetch("before_all", nil), "before_all")
      steps = build_steps(data.fetch("steps", nil))
      after_all = build_hooks(data.fetch("after_all", nil), "after_all")

      Configuration.new(name: pipeline_name, before_all: before_all, steps: steps, after_all: after_all, env: env)
    end

    def extract_pipeline_name(data)
      name = data["name"]

      if name.nil? || (name.is_a?(String) && name.strip.empty?)
        DEFAULT_PIPELINE_NAME
      elsif !name.is_a?(String)
        raise ConfigurationError, 'Invalid pipeline configuration: "name" must be a string'
      else
        name
      end
    end

    def build_steps(steps_data)
      if steps_data.nil?
        raise ConfigurationError, 'Invalid pipeline configuration: missing "steps"'
      end

      unless steps_data.is_a?(Array)
        raise ConfigurationError, 'Invalid pipeline configuration: "steps" must be an array'
      end

      if steps_data.empty?
        raise ConfigurationError, 'Invalid pipeline configuration: "steps" must not be empty'
      end

      steps_data.each_with_index.map do |step_data, index|
        build_step(step_data, "step #{index + 1}", default_when_policy: :success)
      end
    end

    def build_hooks(hooks_data, key)
      return [] if hooks_data.nil?

      unless hooks_data.is_a?(Array)
        raise ConfigurationError, "Invalid pipeline configuration: #{key} must be an array"
      end

      hooks_data.each_with_index.map do |hook_data, index|
        default_when_policy = key == "after_all" ? :always : :success
        build_step(hook_data, "#{key} hook #{index + 1}", default_when_policy: default_when_policy)
      end
    end

    def build_step(step_data, label, default_when_policy:)
      unless step_data.is_a?(Hash)
        raise ConfigurationError, "Invalid pipeline configuration: #{label} must be a mapping"
      end

      unless step_data.key?("name")
        raise ConfigurationError, "Invalid pipeline configuration: #{label} is missing \"name\""
      end

      unless step_data.key?("run")
        raise ConfigurationError, "Invalid pipeline configuration: #{label} is missing \"run\""
      end

      name = step_data["name"]
      command = step_data["run"]
      env = build_env(step_data.fetch("env", nil), "#{label} env")
      timeout = build_timeout(step_data["timeout"], label) if step_data.key?("timeout")
      retries = build_retries(step_data["retries"], label) if step_data.key?("retries")
      retry_delay = build_retry_delay(step_data["retry_delay"], label) if step_data.key?("retry_delay")
      when_policy, when_policy_explicit = build_when_policy(step_data, label, default_when_policy)
      condition = build_condition(step_data["if"], label) if step_data.key?("if")

      unless name.is_a?(String) && !name.strip.empty?
        raise ConfigurationError, "Invalid pipeline configuration: #{label} has a blank name"
      end

      unless command.is_a?(String) && !command.strip.empty?
        raise ConfigurationError, "Invalid pipeline configuration: #{label} has a blank run command"
      end

      Step.new(
        name: name,
        command: command,
        env: env,
        timeout: timeout,
        retries: retries || 0,
        retry_delay: retry_delay || 0,
        when_policy: when_policy,
        condition: condition,
        when_policy_explicit: when_policy_explicit
      )
    end

    def build_when_policy(step_data, label, default_when_policy)
      return [default_when_policy, false] unless step_data.key?("when")

      value = step_data["when"]
      unless value.is_a?(String)
        raise ConfigurationError, "Invalid pipeline configuration: #{label} when must be a string"
      end

      stripped = value.strip
      unless VALID_WHEN_POLICIES.include?(stripped)
        raise ConfigurationError, "Invalid pipeline configuration: #{label} has invalid when value #{value.inspect}"
      end

      [stripped.to_sym, true]
    end

    def build_condition(value, label)
      unless value.is_a?(String)
        raise ConfigurationError, "Invalid pipeline configuration: #{label} if expression must be a string"
      end

      if value.strip.empty?
        raise ConfigurationError, "Invalid pipeline configuration: #{label} if expression is empty"
      end

      ConditionParser.new.parse(value)
    rescue ArgumentError => e
      raise ConfigurationError, "Invalid pipeline configuration: #{label} #{e.message}"
    end

    def build_env(env_data, label)
      return {}.freeze if env_data.nil?

      unless env_data.is_a?(Hash)
        raise ConfigurationError, "Invalid pipeline configuration: #{label} must be a mapping"
      end

      env_data.each_with_object({}) do |(key, value), env|
        variable_name = validate_env_name(key, label)
        env[variable_name] = validate_env_value(variable_name, value, label)
      end.freeze
    end

    def validate_env_name(key, label)
      unless key.is_a?(String)
        raise ConfigurationError, "Invalid pipeline configuration: #{label} contains a non-string environment variable name"
      end

      if key.strip.empty?
        raise ConfigurationError, "Invalid pipeline configuration: #{label} contains a blank environment variable name"
      end

      if key.include?("=")
        raise ConfigurationError, "Invalid pipeline configuration: #{label} variable #{key.inspect} must not contain ="
      end

      if key.include?("\0")
        raise ConfigurationError, "Invalid pipeline configuration: #{label} variable name contains a null byte"
      end

      unless key.match?(ENV_NAME_PATTERN)
        raise ConfigurationError, "Invalid pipeline configuration: #{label} variable #{key.inspect} must use a valid environment variable name"
      end

      key
    end

    def validate_env_value(variable_name, value, label)
      if value.nil?
        raise ConfigurationError, "Invalid pipeline configuration: #{label} variable #{variable_name.inspect} must not be null"
      end

      if value.is_a?(Array) || value.is_a?(Hash)
        raise ConfigurationError, "Invalid pipeline configuration: #{label} variable #{variable_name.inspect} must contain a scalar value"
      end

      string_value = value.to_s

      if string_value.include?("\0")
        raise ConfigurationError, "Invalid pipeline configuration: #{label} variable #{variable_name.inspect} contains a null byte"
      end

      string_value
    end

    def build_timeout(value, label)
      unless value.is_a?(Numeric) && value.finite?
        raise ConfigurationError, "Invalid pipeline configuration: #{label} timeout must be a positive number"
      end

      unless value.positive?
        raise ConfigurationError, "Invalid pipeline configuration: #{label} timeout must be greater than 0"
      end

      value
    end

    def build_retries(value, label)
      unless value.is_a?(Integer) && !value.is_a?(TrueClass) && !value.is_a?(FalseClass) && value >= 0
        raise ConfigurationError, "Invalid pipeline configuration: #{label} retries must be a non-negative integer"
      end

      value
    end

    def build_retry_delay(value, label)
      unless value.is_a?(Numeric) && !value.is_a?(TrueClass) && !value.is_a?(FalseClass) && value.finite? && value >= 0
        raise ConfigurationError, "Invalid pipeline configuration: #{label} retry_delay must be a non-negative number"
      end

      value
    end
  end
end
