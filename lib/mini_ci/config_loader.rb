# frozen_string_literal: true

require "yaml"

module MiniCi
  class ConfigLoader
    DEFAULT_CONFIG_FILE = "pipeline.yml"
    DEFAULT_PIPELINE_NAME = "Mini CI"
    ENV_NAME_PATTERN = /\A[A-Za-z_][A-Za-z0-9_]*\z/

    Configuration = Struct.new(:name, :steps, :env, keyword_init: true)

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
      steps = build_steps(data.fetch("steps", nil))

      Configuration.new(name: pipeline_name, steps: steps, env: env)
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
        build_step(step_data, index + 1)
      end
    end

    def build_step(step_data, step_number)
      unless step_data.is_a?(Hash)
        raise ConfigurationError, "Invalid pipeline configuration: step #{step_number} must be a mapping"
      end

      unless step_data.key?("name")
        raise ConfigurationError, "Invalid pipeline configuration: step #{step_number} is missing \"name\""
      end

      unless step_data.key?("run")
        raise ConfigurationError, "Invalid pipeline configuration: step #{step_number} is missing \"run\""
      end

      name = step_data["name"]
      command = step_data["run"]
      env = build_env(step_data.fetch("env", nil), "step #{step_number} env")

      unless name.is_a?(String) && !name.strip.empty?
        raise ConfigurationError, "Invalid pipeline configuration: step #{step_number} has a blank name"
      end

      unless command.is_a?(String) && !command.strip.empty?
        raise ConfigurationError, "Invalid pipeline configuration: step #{step_number} has a blank run command"
      end

      Step.new(name: name, command: command, env: env)
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
  end
end
