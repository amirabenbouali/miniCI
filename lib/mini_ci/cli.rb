# frozen_string_literal: true

require "time"

require_relative "command_runner"
require_relative "artifact_collector"
require_relative "artifact_manifest"
require_relative "artifact_run_store"
require_relative "cache_store"
require_relative "concurrency_config"
require_relative "config_loader"
require_relative "errors"
require_relative "exit_code"
require_relative "matrix_expander"
require_relative "matrix_runner"
require_relative "pipeline"
require_relative "pipeline_result"
require_relative "plugin"
require_relative "reporter"
require_relative "run_repository"
require_relative "run_serializer"
require_relative "run_output_writer"
require_relative "step"
require_relative "step_result"
require_relative "version"

module MiniCi
  class CLI
    SUCCESS = ExitCode::SUCCESS
    PIPELINE_FAILURE = ExitCode::PIPELINE_FAILURE
    USAGE_ERROR = ExitCode::USAGE_ERROR
    INTERNAL_ERROR = ExitCode::INTERNAL_ERROR
    INTERRUPTED = ExitCode::INTERRUPTED

    HELP_COMMANDS = ["help", "--help", "-h"].freeze
    HELP_OPTIONS = ["--help", "-h"].freeze

    def initialize(arguments:, output: $stdout, error_output: $stderr)
      @arguments = arguments
      @output = output
      @error_output = error_output
    end

    def call
      @debug = extract_debug_option!
      command, *remaining_arguments = @arguments

      return help(remaining_arguments) if command.nil? || HELP_COMMANDS.include?(command)
      return command_help(command) if HELP_OPTIONS.any? { |option| remaining_arguments.delete(option) }

      case command
      when "run"
        run_pipeline(remaining_arguments)
      when "validate"
        validate_pipeline(remaining_arguments)
      when "list"
        list_steps(remaining_arguments)
      when "cache"
        cache_command(remaining_arguments)
      when "plugins"
        plugins_command(remaining_arguments)
      when "dashboard"
        dashboard(remaining_arguments)
      when "version"
        version(remaining_arguments)
      else
        usage_error("unknown command #{command.inspect}")
      end
    rescue ConfigurationError, FileNotFoundError, PluginError => e
      print_error(e.message, type: error_type(e))
      USAGE_ERROR
    rescue UsageError => e
      print_error(e.message, type: "usage")
      USAGE_ERROR
    rescue InternalError => e
      print_error(e.message, type: "internal")
      INTERNAL_ERROR
    rescue Interrupt
      @error_output.puts "Mini CI interrupted."
      INTERRUPTED
    rescue StandardError => e
      print_unexpected_error(e)
      INTERNAL_ERROR
    end

    private

    def extract_debug_option!
      debug = false
      @arguments = @arguments.each_with_object([]) do |argument, kept|
        if argument == "--debug"
          debug = true
        else
          kept << argument
        end
      end
      debug
    end

    def help(arguments = [])
      reject_extra_arguments!("help", arguments)

      @output.puts <<~HELP
        Mini CI

        Usage:
          mini-ci [--debug] run [FILE] [--concurrency N] [--artifacts-dir DIR] [--cache-dir DIR] [--no-cache] [--no-history] [--plugin FILE] [--plugin-dir DIR]
          mini-ci [--debug] validate [FILE] [--plugin FILE] [--plugin-dir DIR]
          mini-ci [--debug] list [FILE] [--plugin FILE] [--plugin-dir DIR]
          mini-ci cache list [--cache-dir DIR]
          mini-ci cache clear --yes [--cache-dir DIR]
          mini-ci plugins list [--plugin FILE] [--plugin-dir DIR]
          mini-ci plugins validate [--plugin FILE] [--plugin-dir DIR]
          mini-ci dashboard [--host HOST] [--port PORT] [--open] [--max-runs N]
          mini-ci version
          mini-ci help

        Commands:
          run       Execute a pipeline
          validate  Validate a pipeline configuration
          list      Display configured pipeline steps
          cache     Inspect or clear the local dependency cache
          plugins   Inspect or validate local Ruby plugins
          dashboard Start the local web dashboard
          version   Display the installed version
          help      Display this help message

        FILE defaults to #{ConfigLoader::DEFAULT_CONFIG_FILE}.
        Exit codes: 0 success, 1 pipeline/runtime failure, 2 usage or configuration error, 3 internal error, 130 interrupted.
      HELP

      SUCCESS
    end

    def command_help(command)
      case command
      when "run"
        @output.puts <<~HELP
          Usage: mini-ci run [FILE] [options]

          Execute a pipeline. FILE defaults to #{ConfigLoader::DEFAULT_CONFIG_FILE}.

          Options:
            --concurrency N       Override matrix concurrency
            -j N                  Alias for --concurrency
            --artifacts-dir DIR   Store artifacts under DIR
            --cache-dir DIR       Store dependency cache under DIR
            --no-cache            Disable dependency cache restore/save
            --no-history          Do not persist this run under .mini-ci/runs
            --plugin FILE         Load a trusted local Ruby plugin
            --plugin-dir DIR      Load trusted Ruby plugins from a directory
            --debug               Print exception details for unexpected internal errors
            --help, -h            Show this help
        HELP
        SUCCESS
      when "validate"
        @output.puts "Usage: mini-ci validate [FILE] [--plugin FILE] [--plugin-dir DIR] [--debug]"
        SUCCESS
      when "list"
        @output.puts "Usage: mini-ci list [FILE] [--plugin FILE] [--plugin-dir DIR] [--debug]"
        SUCCESS
      when "cache"
        @output.puts <<~HELP
          Usage:
            mini-ci cache list [--cache-dir DIR]
            mini-ci cache clear --yes [--cache-dir DIR]
        HELP
        SUCCESS
      when "plugins"
        @output.puts <<~HELP
          Usage:
            mini-ci plugins list [--plugin FILE] [--plugin-dir DIR]
            mini-ci plugins validate [--plugin FILE] [--plugin-dir DIR]
        HELP
        SUCCESS
      when "dashboard"
        @output.puts "Usage: mini-ci dashboard [--host HOST] [--port PORT] [--open] [--max-runs N] [--debug]"
        SUCCESS
      when "version"
        @output.puts "Usage: mini-ci version"
        SUCCESS
      else
        usage_error("unknown command #{command.inspect}")
      end
    end

    def run_pipeline(arguments)
      config_path, concurrency_override, artifacts_dir, cache_dir, cache_enabled, plugin_files, plugin_dirs, history_enabled = run_options_from(arguments)
      registry = load_plugins(plugin_files: plugin_files, plugin_dirs: plugin_dirs)
      registry.freeze!
      config = load_config(config_path, registry: registry)
      history = history_for(config_path, history_enabled)
      run_id = history ? history[:record].fetch("run_id") : "run-#{Time.now.utc.strftime("%Y%m%dT%H%M%SZ")}"
      run_output = history ? TeeOutput.new(@output, history[:output_writer]) : @output
      @active_output = run_output
      plugin_metadata = Plugin::MetadataBuilder.new
      before_run_failure = invoke_plugin_callback(registry, :before_run, plugin_context(configuration: config, run_id: run_id, metadata: plugin_metadata))
      if before_run_failure
        Reporter.new(output: run_output).plugin_failure(before_run_failure)
        history[:repository].fail(run_id, status: "failed", message: before_run_failure.summary) if history
        return PIPELINE_FAILURE
      end

      history[:repository].mark_running(run_id, pipeline_name: config.name, configured_concurrency: concurrency_label(concurrency_override || config.concurrency)) if history
      artifact_store = artifact_store_for(config, artifacts_dir)
      artifact_collector = artifact_store ? ArtifactCollector.new(workspace: Dir.pwd) : nil
      cache_store = cache_enabled ? CacheStore.new(root: cache_dir || CacheStore::DEFAULT_ROOT, workspace: Dir.pwd) : nil
      command_runner = CommandRunner.new(stdout: run_output, stderr: run_output)
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
          plugin_registry: registry,
          plugin_metadata: plugin_metadata,
          run_id: run_id,
          reporter: Reporter.new(output: run_output)
        ).run
        after_run_failure = invoke_plugin_callback(registry, :after_run, plugin_context(result: result, run_id: run_id, metadata: plugin_metadata))
        plugin_failures = result_plugin_failures(result, after_run_failure)
        overall_success = result.success? && plugin_failures.empty?
        Reporter.new(output: run_output).run_summary(result, plugin_failures: plugin_failures)
        write_manifest(artifact_store, result, config.name, matrix: true, registry: registry, metadata: plugin_metadata, plugin_failures: plugin_failures, overall_success: overall_success)
        persist_result(history, result, matrix: true, registry: registry, plugin_metadata: plugin_metadata, plugin_failures: plugin_failures)

        return overall_success ? SUCCESS : PIPELINE_FAILURE
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
        command_runner: command_runner,
        plugin_registry: registry,
        plugin_metadata: plugin_metadata,
        run_id: run_id,
        reporter: Reporter.new(output: run_output)
      ).run
      after_run_failure = invoke_plugin_callback(registry, :after_run, plugin_context(result: result, run_id: run_id, metadata: plugin_metadata))
      plugin_failures = result_plugin_failures(result, after_run_failure)
      overall_success = result.success? && plugin_failures.empty?
      Reporter.new(output: run_output).run_summary(result, plugin_failures: plugin_failures)
      write_manifest(artifact_store, result, config.name, matrix: false, registry: registry, metadata: plugin_metadata, plugin_failures: plugin_failures, overall_success: overall_success)
      persist_result(history, result, matrix: false, registry: registry, plugin_metadata: plugin_metadata, plugin_failures: plugin_failures)

      overall_success ? SUCCESS : PIPELINE_FAILURE
    ensure
      @active_output = nil
    end

    def validate_pipeline(arguments)
      config_path, plugin_files, plugin_dirs = config_options_from(arguments, "validate")
      registry = load_plugins(plugin_files: plugin_files, plugin_dirs: plugin_dirs)
      registry.freeze!
      config = load_config(config_path, registry: registry)

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
      @output.puts "Plugins loaded: #{registry.plugins.length}"
      @output.puts "Plugin item types: #{registry.item_types.length}"
      @output.puts "Plugin validators: #{registry.validators.length}"
      @output.puts "File: #{config_path}"

      SUCCESS
    end

    def list_steps(arguments)
      config_path, plugin_files, plugin_dirs = config_options_from(arguments, "list")
      registry = load_plugins(plugin_files: plugin_files, plugin_dirs: plugin_dirs)
      registry.freeze!
      config = load_config(config_path, registry: registry)

      @output.puts config.name
      @output.puts
      print_plugins(registry)

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
        if step.plugin_item?
          @output.puts "     Uses: #{step.uses}"
          item_type = Plugin.registry.item_type(step.uses)
          @output.puts "     Plugin: #{item_type.plugin.name}" if item_type
          print_plugin_input(step.with)
        else
          @output.puts "     #{step.command}"
        end
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

    def dashboard(arguments)
      require_relative "dashboard/app"
      require_relative "dashboard/configuration"

      configuration = dashboard_options_from(arguments)
      repository = RunRepository.new(workspace: Dir.pwd)
      url = "http://#{configuration.host}:#{configuration.port}"

      if configuration.non_loopback?
        @error_output.puts "Mini CI warning: dashboard is intended for local use and has no authentication."
      end

      @output.puts "Mini CI dashboard running at #{url}"
      @output.puts "Press Ctrl+C to stop."
      open_dashboard(url) if configuration.open_browser

      Dashboard::App.set :repository, repository
      Dashboard::App.set :presenter, Dashboard::Presenter.new(repository: repository)
      Dashboard::App.set :launcher, Dashboard::RunLauncher.new(repository: repository, max_runs: configuration.max_runs)
      Dashboard::App.run!(bind: configuration.host, port: configuration.port, server: "webrick")
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
      plugin_files = []
      plugin_dirs = []
      history_enabled = true

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
        elsif argument == "--no-history"
          history_enabled = false
          remaining.slice!(index, 1)
        elsif argument == "--plugin"
          value = remaining[index + 1]
          raise UsageError, "--plugin requires a value" unless value

          plugin_files << value
          remaining.slice!(index, 2)
        elsif argument == "--plugin-dir"
          value = remaining[index + 1]
          raise UsageError, "--plugin-dir requires a value" unless value

          plugin_dirs << value
          remaining.slice!(index, 2)
        else
          index += 1
        end
      end

      [config_path_from(remaining, "run"), concurrency, artifacts_dir, cache_dir, cache_enabled, plugin_files, plugin_dirs, history_enabled]
    end

    def config_options_from(arguments, command)
      remaining = arguments.dup
      plugin_files = []
      plugin_dirs = []
      index = 0
      while index < remaining.length
        argument = remaining[index]
        if argument == "--plugin"
          value = remaining[index + 1]
          raise UsageError, "--plugin requires a value" unless value

          plugin_files << value
          remaining.slice!(index, 2)
        elsif argument == "--plugin-dir"
          value = remaining[index + 1]
          raise UsageError, "--plugin-dir requires a value" unless value

          plugin_dirs << value
          remaining.slice!(index, 2)
        else
          index += 1
        end
      end

      [config_path_from(remaining, command), plugin_files, plugin_dirs]
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

    def plugins_command(arguments)
      subcommand, *remaining = arguments
      plugin_files, plugin_dirs = plugin_options_from(remaining)
      registry = load_plugins(plugin_files: plugin_files, plugin_dirs: plugin_dirs)
      registry.freeze!

      case subcommand
      when "list"
        @output.puts "Loaded plugins"
        @output.puts
        print_plugin_details(registry)
        SUCCESS
      when "validate"
        @output.puts "Plugin validation passed."
        @output.puts
        @output.puts "Plugins: #{registry.plugins.length}"
        @output.puts "Callbacks: #{MiniCi::Plugin::Definition::CALLBACK_EVENTS.sum { |event| registry.callbacks_for(event).length }}"
        @output.puts "Custom item types: #{registry.item_types.length}"
        @output.puts "Validators: #{registry.validators.length}"
        SUCCESS
      else
        usage_error("plugins requires list or validate")
      end
    end

    def plugin_options_from(arguments)
      remaining = arguments.dup
      plugin_files = []
      plugin_dirs = []
      index = 0
      while index < remaining.length
        argument = remaining[index]
        if argument == "--plugin"
          value = remaining[index + 1]
          raise UsageError, "--plugin requires a value" unless value

          plugin_files << value
          remaining.slice!(index, 2)
        elsif argument == "--plugin-dir"
          value = remaining[index + 1]
          raise UsageError, "--plugin-dir requires a value" unless value

          plugin_dirs << value
          remaining.slice!(index, 2)
        else
          index += 1
        end
      end

      reject_extra_arguments!("plugins", remaining)
      [plugin_files, plugin_dirs]
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

    def dashboard_options_from(arguments)
      remaining = arguments.dup
      host = "127.0.0.1"
      port = 4567
      max_runs = 200
      open_browser = false
      index = 0

      while index < remaining.length
        argument = remaining[index]
        case argument
        when "--host"
          value = remaining[index + 1]
          raise UsageError, "--host requires a value" unless value

          host = value
          remaining.slice!(index, 2)
        when "--port"
          value = remaining[index + 1]
          raise UsageError, "--port requires a value" unless value

          port = value
          remaining.slice!(index, 2)
        when "--max-runs"
          value = remaining[index + 1]
          raise UsageError, "--max-runs requires a value" unless value

          max_runs = value
          remaining.slice!(index, 2)
        when "--open"
          open_browser = true
          remaining.slice!(index, 1)
        else
          index += 1
        end
      end

      reject_extra_arguments!("dashboard", remaining)
      Dashboard::Configuration.new(host: host, port: port, max_runs: max_runs, open_browser: open_browser)
    rescue ArgumentError
      raise UsageError, "dashboard port and max-runs must be integers"
    end

    def open_dashboard(url)
      if RUBY_PLATFORM.match?(/darwin/)
        system("open", url)
      elsif RUBY_PLATFORM.match?(/linux/)
        system("xdg-open", url)
      end
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

    def load_config(config_path, registry: Plugin.registry)
      ConfigLoader.new(path: config_path, plugin_registry: registry).load
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

    def write_manifest(artifact_store, result, pipeline_name, matrix:, registry: Plugin.registry, metadata: nil, plugin_failures: [], overall_success: nil)
      return unless artifact_store

      manifest = ArtifactManifest.new(store: artifact_store, plugin_registry: registry, plugin_metadata: metadata, plugin_failures: plugin_failures)
      if matrix
        manifest.write_for_matrix(result, pipeline_name: pipeline_name, overall_success: overall_success)
      else
        manifest.write_for_pipeline(result, pipeline_name: pipeline_name, overall_success: overall_success)
      end
    end

    def result_plugin_failures(result, after_run_failure)
      failures =
        if result.respond_to?(:plugin_failures)
          result.plugin_failures
        elsif result.respond_to?(:matrix_job_results)
          result.matrix_job_results.flat_map { |job| job.pipeline_result.plugin_failures }
        else
          []
        end
      failures + [after_run_failure].compact
    end

    def load_plugins(plugin_files:, plugin_dirs:)
      Plugin.reset!
      registry = Plugin.registry
      Plugin::Loader.new(registry: registry, workspace: Dir.pwd).load(
        default: true,
        directories: plugin_dirs,
        files: plugin_files
      )
      registry
    end

    def invoke_plugin_callback(registry, event, context)
      Plugin::Runner.new(registry: registry).invoke(event, context)
    end

    def plugin_context(configuration: nil, result: nil, run_id:, metadata:)
      Plugin::Context.new(
        configuration: configuration,
        result: result,
        workspace: Dir.pwd,
        run_id: run_id,
        metadata: metadata,
        output: @active_output || @output
      )
    end

    def history_for(config_path, enabled)
      return nil unless enabled

      repository = RunRepository.new(workspace: Dir.pwd)
      record = repository.create(pipeline_file: config_path, source: "cli")
      {
        repository: repository,
        record: record,
        output_writer: repository.output_writer(record.fetch("run_id"))
      }
    end

    def persist_result(history, result, matrix:, registry:, plugin_metadata:, plugin_failures:)
      return unless history

      payload = RunSerializer.new.serialize_result(
        result,
        matrix: matrix,
        registry: registry,
        plugin_metadata: plugin_metadata,
        plugin_failures: plugin_failures
      )
      history[:repository].finish(history[:record].fetch("run_id"), payload)
      history[:repository].prune(max_runs: 200)
    end

    def concurrency_label(concurrency)
      return nil unless concurrency

      concurrency.automatic? ? "automatic" : concurrency.value
    end

    def print_plugins(registry)
      return if registry.plugins.empty?

      @output.puts "Plugins: #{registry.plugins.map { |plugin| "#{plugin.name} #{plugin.version}" }.join(", ")}"
      @output.puts
    end

    def print_plugin_details(registry)
      if registry.plugins.empty?
        @output.puts "No plugins loaded."
        return
      end

      registry.plugins.each_with_index do |plugin, index|
        @output.puts "#{index + 1}. #{plugin.name} #{plugin.version}"
        @output.puts "   #{plugin.description}" if plugin.description
        @output.puts "   Source: #{plugin.source_path}" if plugin.source_path
        item_types = plugin.item_types.map(&:name)
        @output.puts "   Item types: #{item_types.join(", ")}" unless item_types.empty?
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

    def print_plugin_input(input)
      return if input.empty?

      @output.puts "     Input:"
      input.each do |key, value|
        @output.puts "       #{key}: #{value}"
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
      print_error(message, type: "usage")
      @error_output.puts
      @error_output.puts "Run `mini-ci help` for usage information."
      USAGE_ERROR
    end

    def print_error(message, type: "error")
      @error_output.puts "Mini CI #{type} error: #{message}"
    end

    def error_type(error)
      case error
      when ConfigurationError, FileNotFoundError
        "configuration"
      when PluginError
        "plugin"
      else
        "error"
      end
    end

    def print_unexpected_error(error)
      @error_output.puts "Mini CI internal error: an unexpected error occurred."
      @error_output.puts "Run again with --debug for details."
      return unless @debug

      @error_output.puts
      @error_output.puts "#{error.class}: #{error.message}"
      Array(error.backtrace).each { |line| @error_output.puts line }
    end
  end
end
