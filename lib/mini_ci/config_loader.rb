# frozen_string_literal: true

require "yaml"
require "pathname"

require_relative "artifact_definition"
require_relative "cache_definition"
require_relative "cache_key_resolver"
require_relative "condition_parser"
require_relative "concurrency_config"
require_relative "matrix_definition"
require_relative "matrix_expander"
require_relative "plugin"

module MiniCi
  class ConfigLoader
    DEFAULT_CONFIG_FILE = "pipeline.yml"
    DEFAULT_PIPELINE_NAME = "Mini CI"
    ENV_NAME_PATTERN = /\A[A-Za-z_][A-Za-z0-9_]*\z/
    VALID_WHEN_POLICIES = %w[success failure always never].freeze

    Configuration = Struct.new(:name, :before_all, :steps, :after_all, :env, :matrix, :concurrency, :name_explicit,
                               keyword_init: true)

    def initialize(path: DEFAULT_CONFIG_FILE, plugin_registry: Plugin.registry)
      @path = path
      @plugin_registry = plugin_registry
    end

    def load
      file_path = locate_file
      data = parse_yaml(file_path)
      validate_and_build(data)
    end

    private

    def locate_file
      expanded = File.expand_path(@path)

      raise FileNotFoundError, "#{@path} was not found" unless File.file?(expanded)

      expanded
    end

    def parse_yaml(file_path)
      content = File.read(file_path, encoding: Encoding::UTF_8)
      reject_duplicate_yaml_keys(content, file_path)
      YAML.safe_load(content, aliases: false)
    rescue Psych::Exception => e
      raise ConfigurationError, "Invalid YAML in #{File.basename(file_path)}: #{e.message}"
    end

    def reject_duplicate_yaml_keys(content, file_path)
      tree = Psych.parse_stream(content, filename: file_path)
      tree.children.each do |document|
        check_mapping_keys(document.root) if document.root
      end
    end

    def check_mapping_keys(node)
      if node.is_a?(Psych::Nodes::Mapping)
        seen_keys = {}

        node.children.each_slice(2) do |key_node, value_node|
          if key_node.is_a?(Psych::Nodes::Scalar)
            if seen_keys.key?(key_node.value)
              raise ConfigurationError, "Invalid pipeline configuration: duplicate key #{key_node.value.inspect}"
            end

            seen_keys[key_node.value] = true
          end

          check_mapping_keys(value_node)
        end
      elsif node.respond_to?(:children)
        Array(node.children).each { |child| check_mapping_keys(child) }
      end
    end

    def validate_and_build(data)
      unless data.is_a?(Hash)
        raise ConfigurationError, "Invalid pipeline configuration: expected a mapping at the top level"
      end

      pipeline_name, name_explicit = extract_pipeline_name(data)
      env = build_env(data.fetch("env", nil), "global env")
      matrix = build_matrix(data.fetch("matrix", nil))
      concurrency = build_concurrency(data)
      before_all = build_hooks(data.fetch("before_all", nil), "before_all")
      steps = build_steps(data.fetch("steps", nil))
      after_all = build_hooks(data.fetch("after_all", nil), "after_all")

      configuration = Configuration.new(
        name: pipeline_name,
        before_all: before_all,
        steps: steps,
        after_all: after_all,
        env: env,
        matrix: matrix,
        concurrency: concurrency,
        name_explicit: name_explicit
      )
      run_plugin_validators(configuration)
      configuration
    end

    def extract_pipeline_name(data)
      name = data["name"]

      if name.nil? || (name.is_a?(String) && name.strip.empty?)
        [DEFAULT_PIPELINE_NAME, false]
      elsif !name.is_a?(String)
        raise ConfigurationError, 'Invalid pipeline configuration: "name" must be a string'
      else
        [name, true]
      end
    end

    def build_steps(steps_data)
      raise ConfigurationError, 'Invalid pipeline configuration: missing "steps"' if steps_data.nil?

      unless steps_data.is_a?(Array)
        raise ConfigurationError, 'Invalid pipeline configuration: "steps" must be an array'
      end

      raise ConfigurationError, 'Invalid pipeline configuration: "steps" must not be empty' if steps_data.empty?

      steps_data.each_with_index.map do |step_data, index|
        build_step(step_data, "step #{index + 1}", default_when_policy: :success)
      end
    end

    def build_hooks(hooks_data, key)
      return [] if hooks_data.nil?

      raise ConfigurationError, "Invalid pipeline configuration: #{key} must be an array" unless hooks_data.is_a?(Array)

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

      has_run = step_data.key?("run")
      has_uses = step_data.key?("uses")
      if has_run && has_uses
        raise ConfigurationError, "Invalid pipeline configuration: #{label} cannot define both run and uses"
      end

      raise ConfigurationError, "Invalid pipeline configuration: #{label} is missing \"run\"" unless has_run || has_uses

      name = step_data["name"]
      command = step_data["run"] if has_run
      uses = build_uses(step_data["uses"], label) if has_uses
      with = build_with(step_data.fetch("with", {}), label) if has_uses
      env = build_env(step_data.fetch("env", nil), "#{label} env")
      timeout = build_timeout(step_data["timeout"], label) if step_data.key?("timeout")
      retries = build_retries(step_data["retries"], label) if step_data.key?("retries")
      retry_delay = build_retry_delay(step_data["retry_delay"], label) if step_data.key?("retry_delay")
      when_policy, when_policy_explicit = build_when_policy(step_data, label, default_when_policy)
      condition = build_condition(step_data["if"], label) if step_data.key?("if")
      artifacts = build_artifacts(step_data["artifacts"], label) if step_data.key?("artifacts")
      cache = build_cache(step_data["cache"], label) if step_data.key?("cache")
      if has_uses && step_data.key?("timeout")
        raise ConfigurationError, "Invalid pipeline configuration: #{label} plugin items do not support timeout"
      end
      if has_uses && (retries || 0).positive?
        raise ConfigurationError, "Invalid pipeline configuration: #{label} plugin items do not support retries"
      end

      unless name.is_a?(String) && !name.strip.empty?
        raise ConfigurationError, "Invalid pipeline configuration: #{label} has a blank name"
      end

      if has_run && !(command.is_a?(String) && !command.strip.empty?)
        raise ConfigurationError, "Invalid pipeline configuration: #{label} has a blank run command"
      end

      validate_plugin_item(uses, with, label) if uses

      Step.new(
        name: name,
        command: command,
        env: env,
        timeout: timeout,
        retries: retries || 0,
        retry_delay: retry_delay || 0,
        when_policy: when_policy,
        condition: condition,
        when_policy_explicit: when_policy_explicit,
        artifacts: artifacts,
        cache: cache,
        uses: uses,
        with: with || {}
      )
    end

    def build_uses(value, label)
      unless value.is_a?(String) && !value.strip.empty?
        raise ConfigurationError, "Invalid pipeline configuration: #{label} uses must be a non-empty string"
      end

      unless @plugin_registry.item_type(value)
        raise ConfigurationError,
              %(Invalid pipeline configuration: #{label} references unknown plugin item type "#{value}")
      end

      value
    end

    def build_with(value, label)
      unless value.is_a?(Hash)
        raise ConfigurationError, "Invalid pipeline configuration: #{label} with must be a mapping"
      end

      value.dup.freeze
    end

    def validate_plugin_item(uses, with, label)
      item_type = @plugin_registry.item_type(uses)
      errors = item_type.validate(with)
      return if errors.empty?

      raise ConfigurationError, "Plugin validation failed [#{item_type.plugin.name}:#{uses} #{label}]: #{errors.first}"
    rescue StandardError => e
      raise ConfigurationError, "Plugin validation failed [#{item_type.plugin.name}:#{uses} #{label}]: #{e.message}"
    end

    def run_plugin_validators(configuration)
      @plugin_registry.validators.each do |plugin, validator|
        messages = validator.call(configuration)
        Array(messages).compact.each do |message|
          raise ConfigurationError, "Plugin validation failed [#{plugin.name}]: #{message}"
        end
      rescue ConfigurationError
        raise
      rescue StandardError => e
        raise ConfigurationError, "Plugin validation failed [#{plugin.name}]: #{e.message}"
      end
    end

    def build_cache(cache_data, label)
      unless cache_data.is_a?(Hash)
        raise ConfigurationError, "Invalid pipeline configuration: #{label} cache must be a mapping"
      end

      unknown_fields = cache_data.keys - %w[key paths restore_keys save_when]
      unless unknown_fields.empty?
        raise ConfigurationError,
              "Invalid pipeline configuration: #{label} cache contains unknown field #{unknown_fields.first.inspect}"
      end

      unless cache_data.key?("key")
        raise ConfigurationError, "Invalid pipeline configuration: #{label} cache is missing \"key\""
      end

      unless cache_data.key?("paths")
        raise ConfigurationError, "Invalid pipeline configuration: #{label} cache paths must be a non-empty array"
      end

      restore_keys = cache_data.fetch("restore_keys", [])
      unless restore_keys.is_a?(Array)
        raise ConfigurationError, "Invalid pipeline configuration: #{label} cache restore_keys must be an array"
      end

      validate_cache_template(cache_data["key"], "#{label} cache key")
      restore_keys.each_with_index do |restore_key, index|
        validate_cache_template(restore_key, "#{label} cache restore key #{index + 1}")
      end

      CacheDefinition.new(
        key: cache_data["key"],
        paths: cache_data["paths"],
        restore_keys: restore_keys,
        save_when: cache_data.fetch("save_when", :success)
      )
    rescue ArgumentError => e
      raise ConfigurationError, "Invalid pipeline configuration: #{label} #{e.message}"
    end

    def validate_cache_template(value, label)
      unless value.is_a?(String) && !value.strip.empty? && !value.include?("\0")
        raise ConfigurationError, "Invalid pipeline configuration: #{label} must be a non-empty string"
      end

      CacheKeyResolver.new(workspace: Dir.pwd).validate_template!(value)
    end

    def build_artifacts(artifact_data, label)
      unless artifact_data.is_a?(Hash)
        raise ConfigurationError, "Invalid pipeline configuration: #{label} artifacts must be a mapping"
      end

      unknown_fields = artifact_data.keys - %w[paths when]
      unless unknown_fields.empty?
        raise ConfigurationError,
              "Invalid pipeline configuration: #{label} artifacts contains unknown field #{unknown_fields.first.inspect}"
      end

      unless artifact_data.key?("paths")
        raise ConfigurationError, "Invalid pipeline configuration: #{label} artifacts paths must be a non-empty array"
      end

      paths = artifact_data["paths"]
      unless paths.is_a?(Array) && !paths.empty?
        raise ConfigurationError, "Invalid pipeline configuration: #{label} artifacts paths must be a non-empty array"
      end

      paths.each_with_index do |path, index|
        validate_artifact_path(path, label, index)
      end

      when_policy = artifact_data.fetch("when", "always")
      unless when_policy.is_a?(String) && ArtifactDefinition::VALID_POLICIES.include?(when_policy.to_sym)
        raise ConfigurationError,
              "Invalid pipeline configuration: #{label} artifacts when must be one of success, failure, always"
      end

      ArtifactDefinition.new(paths: paths, when_policy: when_policy.to_sym)
    end

    def validate_artifact_path(path, label, index)
      unless path.is_a?(String) && !path.strip.empty?
        raise ConfigurationError,
              "Invalid pipeline configuration: #{label} artifact path #{index + 1} must be a non-empty string"
      end

      return unless Pathname.new(path).absolute? || path.split(%r{[\\/]+}).include?("..")

      raise ConfigurationError,
            "Invalid pipeline configuration: #{label} artifact path #{index + 1} must stay inside the workspace"
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

      raise ConfigurationError, "Invalid pipeline configuration: #{label} if expression is empty" if value.strip.empty?

      ConditionParser.new.parse(value)
    rescue ArgumentError => e
      raise ConfigurationError, "Invalid pipeline configuration: #{label} #{e.message}"
    end

    def build_matrix(matrix_data)
      return nil if matrix_data.nil?

      unless matrix_data.is_a?(Hash)
        raise ConfigurationError, "Invalid pipeline configuration: matrix must be a mapping"
      end

      raise ConfigurationError, "Invalid pipeline configuration: matrix must not be empty" if matrix_data.empty?

      dimensions = matrix_data.each_with_object({}) do |(key, values), matrix|
        matrix_key = validate_matrix_key(key)
        matrix[matrix_key] = build_matrix_values(matrix_key, values)
      end

      definition = MatrixDefinition.new(dimensions)
      if definition.total_combination_count > MatrixExpander::MAX_JOBS
        raise ConfigurationError,
              "Invalid pipeline configuration: matrix expands to #{definition.total_combination_count} jobs, exceeding the limit of #{MatrixExpander::MAX_JOBS}"
      end

      definition
    end

    def build_concurrency(data)
      return ConcurrencyConfig.new(nil) unless data.key?("concurrency")

      value = data["concurrency"]
      raise ConfigurationError, "Invalid pipeline configuration: concurrency must be a positive integer" if value.nil?

      ConcurrencyConfig.new(value)
    end

    def validate_matrix_key(key)
      unless key.is_a?(String) && key.match?(ENV_NAME_PATTERN)
        raise ConfigurationError, "Invalid pipeline configuration: matrix key #{key.inspect} is invalid"
      end

      key
    end

    def build_matrix_values(key, values)
      unless values.is_a?(Array)
        raise ConfigurationError,
              "Invalid pipeline configuration: matrix value list for #{key.inspect} must be an array"
      end

      if values.empty?
        raise ConfigurationError,
              "Invalid pipeline configuration: matrix value list for #{key.inspect} must not be empty"
      end

      values.each_with_index.map do |value, index|
        if value.nil? || value.is_a?(Array) || value.is_a?(Hash)
          raise ConfigurationError,
                "Invalid pipeline configuration: matrix value #{index + 1} for #{key.inspect} must be a scalar"
        end

        value.to_s
      end.freeze
    end

    def build_env(env_data, label)
      return {}.freeze if env_data.nil?

      raise ConfigurationError, "Invalid pipeline configuration: #{label} must be a mapping" unless env_data.is_a?(Hash)

      env_data.each_with_object({}) do |(key, value), env|
        variable_name = validate_env_name(key, label)
        env[variable_name] = validate_env_value(variable_name, value, label)
      end.freeze
    end

    def validate_env_name(key, label)
      unless key.is_a?(String)
        raise ConfigurationError,
              "Invalid pipeline configuration: #{label} contains a non-string environment variable name"
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
        raise ConfigurationError,
              "Invalid pipeline configuration: #{label} variable #{key.inspect} must use a valid environment variable name"
      end

      key
    end

    def validate_env_value(variable_name, value, label)
      if value.nil?
        raise ConfigurationError,
              "Invalid pipeline configuration: #{label} variable #{variable_name.inspect} must not be null"
      end

      if value.is_a?(Array) || value.is_a?(Hash)
        raise ConfigurationError,
              "Invalid pipeline configuration: #{label} variable #{variable_name.inspect} must contain a scalar value"
      end

      string_value = value.to_s

      if string_value.include?("\0")
        raise ConfigurationError,
              "Invalid pipeline configuration: #{label} variable #{variable_name.inspect} contains a null byte"
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
