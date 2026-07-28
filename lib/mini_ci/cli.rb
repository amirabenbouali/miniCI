# frozen_string_literal: true

require_relative "command_runner"
require_relative "artifact_collector"
require_relative "artifact_manifest"
require_relative "artifact_run_store"
require_relative "cache_store"
require_relative "concurrency_config"
require_relative "config_loader"
require_relative "errors"
require_relative "matrix_expander"
require_relative "matrix_runner"
require_relative "pipeline"
require_relative "pipeline_result"
require_relative "reporter"
require_relative "step"
require_relative "step_result"
require_relative "version"

module MiniCi
  class CLI
    SUCCESS = 0
    PIPELINE_FAILURE = 1
    USAGE_ERROR = 2
    INTERNAL_ERROR = 3

    HELP_COMMANDS = ["help", "--help", "-h"].freeze

    def initialize(arguments:, output: $stdout, error_output: $stderr)
      @arguments = arguments
      @output = output
      @error_output = error_output
    end

    def call
      command, *remaining_arguments = @arguments

      return help(remaining_arguments) if command.nil? || HELP_COMMANDS.include?(command)

      case command
      when "run"
        run_pipeline(remaining_arguments)
      when "validate"
        validate_pipeline(remaining_arguments)
      when "list"
        list_steps(remaining_arguments)
      when "cache"
        cache_command(remaining_arguments)
      when "version"
        version(remaining_arguments)
      else
        usage_error("unknown command #{command.inspect}")
      end
    rescue ConfigurationError, FileNotFoundError => e
      print_error(e.message)
      USAGE_ERROR
    rescue UsageError => e
      print_error(e.message)
      USAGE_ERROR
    rescue InternalError => e
      print_error(e.message)
      INTERNAL_ERROR
    end

    private

    def help(arguments = [])
      reject_extra_arguments!("help", arguments)

      @output.puts <<~HELP
        Mini CI

        Usage:
          mini-ci run [FILE] [--concurrency N] [--artifacts-dir DIR] [--cache-dir DIR] [--no-cache]
          mini-ci validate [FILE]
          mini-ci list [FILE]
          mini-ci cache list [--cache-dir DIR]
          mini-ci cache clear --yes [--cache-dir DIR]
          mini-ci version
          mini-ci help

        Commands:
          run       Execute a pipeline
          validate  Validate a pipeline configuration
          list      Display configured pipeline steps
          cache     Inspect or clear the local dependency cache
          version   Display the installed version
          help      Display this help message

        FILE defaults to #{ConfigLoader::DEFAULT_CONFIG_FILE}.
      HELP

      SUCCESS
    end

    def run_pipeline(arguments)
      config_path, concurrency_override, artifacts_dir, cache_dir, cache_enabled = run_options_from(arguments)
      config = load_config(config_path)
      artifact_store = artifact_store_for(config, artifacts_dir)
      artifact_collector = artifact_store ? ArtifactCollector.new(workspace: Dir.pwd) : nil
      cache_store = cache_enabled ? CacheStore.new(root: cache_dir || CacheStore::DEFAULT_ROOT, workspace: Dir.pwd) : nil
      if config.matrix
        result = MatrixRunner.new(
          name: config.name,
          name_explicit: config.name_explicit,
          matrix_definition: config.matrix,
          before_all: config.before_all,
          steps: config.steps,
          after_all: config.after_all,
          env: config.env,
          concurrency: concurrency_override || config.concurrency,
          artifact_collector: artifact_collector,
          artifact_store: artifact_store,
          cache_store: cache_store,
          cache_enabled: cache_enabled,
          reporter: Reporter.new(output: @output)
        ).run
        write_manifest(artifact_store, result, config.name, matrix: true)

        return result.success? ? SUCCESS : PIPELINE_FAILURE
      end

      artifact_job_directory = artifact_store&.job_directory(index: 1)
      result = Pipeline.new(
        name: config.name,
        before_all: config.before_all,
        steps: config.steps,
        after_all: config.after_all,
        env: config.env,
        artifact_collector: artifact_collector,
        artifact_store: artifact_store,
        artifact_job_directory: artifact_job_directory,
        cache_store: cache_store,
        cache_enabled: cache_enabled,
        reporter: Reporter.new(output: @output)
      ).run
      write_manifest(artifact_store, result, config.name, matrix: false)

      result.success? ? SUCCESS : PIPELINE_FAILURE
    end

    def validate_pipeline(arguments)
      config_path = config_path_from(arguments, "validate")
      config = load_config(config_path)

      @output.puts "Pipeline configuration is valid."
      @output.puts
      @output.puts "Name: #{config.name}"
      print_concurrency_validation(config.concurrency)
      print_matrix_validation(config.matrix) if config.matrix
      @output.puts "Before-all hooks: #{config.before_all.length}"
      @output.puts "Steps: #{config.steps.length}"
      @output.puts "After-all hooks: #{config.after_all.length}"
      @output.puts "Environment variables: #{config.env.length}"
      @output.puts "Conditional items: #{conditional_item_count(config)}"
      @output.puts "Artifact-producing items: #{artifact_item_count(config)}"
      @output.puts "Cache-producing items: #{cache_item_count(config)}"
      @output.puts "File: #{config_path}"

      SUCCESS
    end

    def list_steps(arguments)
      config_path = config_path_from(arguments, "list")
      config = load_config(config_path)

      @output.puts config.name
      @output.puts

      print_global_environment(config.env)
      print_concurrency(config.concurrency)
      print_matrix(config.matrix) if config.matrix

      print_phase("Before all", config.before_all)
      print_phase("Steps", config.steps)
      print_phase("After all", config.after_all)

      SUCCESS
    end

    def print_phase(heading, steps)
      return if steps.empty?

      @output.puts "#{heading}:"
      steps.each_with_index do |step, index|
        @output.puts "  #{index + 1}. #{step.name}"
        @output.puts "     #{step.command}"
        @output.puts "     Timeout: #{format_timeout(step.timeout)}" if step.timeout
        @output.puts "     Retries: #{step.retries}" if step.retries.positive?
        @output.puts "     Retry delay: #{format_duration(step.retry_delay)}" if step.retries.positive? && step.retry_delay.positive?
        @output.puts "     When: #{step.when_policy}" if step.when_policy_explicit?
        @output.puts "     If: #{step.condition.source}" if step.condition
        print_artifacts(step.artifacts)
        print_cache(step.cache)
        print_step_environment(step.env)
        @output.puts
      end
    end

    def version(arguments)
      reject_extra_arguments!("version", arguments)

      @output.puts "Mini CI #{VERSION}"
      SUCCESS
    end

    def config_path_from(arguments, command)
      if arguments.length > 1
        raise UsageError, "#{command} accepts at most one file argument"
      end

      arguments.fetch(0, ConfigLoader::DEFAULT_CONFIG_FILE)
    end

    def run_options_from(arguments)
      remaining = arguments.dup
      concurrency = nil
      artifacts_dir = nil
      cache_dir = nil
      cache_enabled = true

      index = 0
      while index < remaining.length
        argument = remaining[index]
        if argument == "--concurrency" || argument == "-j"
          value = remaining[index + 1]
          raise UsageError, "#{argument} requires a value" unless value

          concurrency = parse_concurrency_override(value)
          remaining.slice!(index, 2)
        elsif argument == "--artifacts-dir"
          value = remaining[index + 1]
          raise UsageError, "--artifacts-dir requires a value" unless value

          artifacts_dir = value
          remaining.slice!(index, 2)
        elsif argument == "--cache-dir"
          value = remaining[index + 1]
          raise UsageError, "--cache-dir requires a value" unless value

          cache_dir = value
          remaining.slice!(index, 2)
        elsif argument == "--no-cache"
          cache_enabled = false
          remaining.slice!(index, 1)
        else
          index += 1
        end
      end

      [config_path_from(remaining, "run"), concurrency, artifacts_dir, cache_dir, cache_enabled]
    end

    def cache_command(arguments)
      subcommand, *remaining = arguments
      case subcommand
      when "list"
        cache_list(remaining)
      when "clear"
        cache_clear(remaining)
      else
        usage_error("cache requires list or clear")
      end
    end

    def cache_list(arguments)
      cache_dir = cache_options_from(arguments, command: "cache list")
      store = CacheStore.new(root: cache_dir || CacheStore::DEFAULT_ROOT, workspace: Dir.pwd)
      entries = store.list_entries

      @output.puts "Cache directory: #{store.root}"
      if entries.empty?
        @output.puts "No cache entries."
      else
        entries.each_with_index do |entry, index|
          @output.puts "#{index + 1}. #{entry.key}"
          @output.puts "   Files: #{entry.file_count}"
          @output.puts "   Size: #{entry.size_bytes} bytes"
          @output.puts "   Created: #{entry.created_at.iso8601 if entry.created_at}"
        end
      end
      SUCCESS
    end

    def cache_clear(arguments)
      yes = false
      remaining = arguments.dup
      if remaining.include?("--yes")
        yes = true
        remaining.delete("--yes")
      end

      cache_dir = cache_options_from(remaining, command: "cache clear")
      unless yes
        @output.puts "Cache clear requires --yes."
        return USAGE_ERROR
      end

      store = CacheStore.new(root: cache_dir || CacheStore::DEFAULT_ROOT, workspace: Dir.pwd)
      count = store.clear!
      @output.puts "Cleared #{count} cache entries from #{store.root}."
      SUCCESS
    end

    def cache_options_from(arguments, command:)
      remaining = arguments.dup
      cache_dir = nil
      index = 0
      while index < remaining.length
        argument = remaining[index]
        if argument == "--cache-dir"
          value = remaining[index + 1]
          raise UsageError, "--cache-dir requires a value" unless value

          cache_dir = value
          remaining.slice!(index, 2)
        else
          index += 1
        end
      end

      reject_extra_arguments!(command, remaining)
      cache_dir
    end

    def parse_concurrency_override(value)
      unless value.match?(/\A[1-9][0-9]*\z/)
        raise UsageError, "concurrency must be a positive integer"
      end

      ConcurrencyConfig.new(value.to_i)
    end

    def reject_extra_arguments!(command, arguments)
      return if arguments.empty?

      raise UsageError, "#{command} does not accept extra arguments"
    end

    def load_config(config_path)
      ConfigLoader.new(path: config_path).load
    end

    def conditional_item_count(config)
      (config.before_all + config.steps + config.after_all).count do |step|
        step.when_policy_explicit? || step.condition
      end
    end

    def artifact_item_count(config)
      (config.before_all + config.steps + config.after_all).count(&:artifacts)
    end

    def cache_item_count(config)
      (config.before_all + config.steps + config.after_all).count(&:cache)
    end

    def artifact_store_for(config, artifacts_dir)
      return nil unless artifacts_dir || artifact_item_count(config).positive?

      ArtifactRunStore.new(root: artifacts_dir || ArtifactRunStore::DEFAULT_ROOT, workspace: Dir.pwd)
    end

    def write_manifest(artifact_store, result, pipeline_name, matrix:)
      return unless artifact_store

      manifest = ArtifactManifest.new(store: artifact_store)
      if matrix
        manifest.write_for_matrix(result, pipeline_name: pipeline_name)
      else
        manifest.write_for_pipeline(result, pipeline_name: pipeline_name)
      end
    end

    def print_matrix_validation(matrix)
      @output.puts "Matrix dimensions: #{matrix.dimension_count}"
      @output.puts "Generated jobs: #{matrix.total_combination_count}"
    end

    def print_concurrency_validation(concurrency)
      @output.puts "Configured concurrency: #{concurrency.automatic? ? "automatic" : concurrency.value}"
    end

    def print_concurrency(concurrency)
      @output.puts "Concurrency: #{concurrency.automatic? ? "automatic" : concurrency.value}"
      @output.puts
    end

    def print_matrix(matrix)
      return unless matrix

      combinations = MatrixExpander.new.expand(matrix)

      @output.puts "Matrix:"
      matrix.dimensions.each do |key, values|
        @output.puts "  #{key}: #{values.join(", ")}"
      end
      @output.puts
      @output.puts "Generated jobs: #{combinations.length}"
      @output.puts
      print_combinations(combinations)
    end

    def print_combinations(combinations)
      display_limit = 20
      shown = combinations.first(display_limit)
      @output.puts "Combinations:"
      shown.each_with_index do |combination, index|
        @output.puts "  #{index + 1}. #{combination.label}"
      end
      if combinations.length > display_limit
        @output.puts "  ... #{combinations.length - display_limit} more"
      end
      @output.puts
    end

    def print_global_environment(env)
      return if env.empty?

      @output.puts "Global environment:"
      env.each do |name, value|
        @output.puts "  #{name}=#{value}"
      end
      @output.puts
    end

    def print_step_environment(env)
      return if env.empty?

      @output.puts "     Environment:"
      env.each do |name, value|
        @output.puts "       #{name}=#{value}"
      end
    end

    def print_artifacts(artifacts)
      return unless artifacts

      @output.puts "     Artifacts:"
      @output.puts "       When: #{artifacts.when_policy}"
      @output.puts "       Paths:"
      artifacts.paths.each do |path|
        @output.puts "         - #{path}"
      end
    end

    def print_cache(cache)
      return unless cache

      @output.puts "     Cache:"
      @output.puts "       Key: #{cache.key}"
      unless cache.restore_keys.empty?
        @output.puts "       Restore keys:"
        cache.restore_keys.each { |key| @output.puts "         - #{key}" }
      end
      @output.puts "       Save when: #{cache.save_when}"
      @output.puts "       Paths:"
      cache.paths.each do |path|
        @output.puts "         - #{path}"
      end
    end

    def format_timeout(timeout)
      if timeout.is_a?(Integer)
        "#{timeout}s"
      else
        "#{timeout}s"
      end
    end

    def format_duration(seconds)
      format("%.2fs", seconds)
    end

    def usage_error(message)
      print_error(message)
      @error_output.puts
      @error_output.puts "Run `mini-ci help` for usage information."
      USAGE_ERROR
    end

    def print_error(message)
      @error_output.puts "Mini CI error: #{message}"
    end
  end
end
