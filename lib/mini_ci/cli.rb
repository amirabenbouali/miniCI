# frozen_string_literal: true

require_relative "command_runner"
require_relative "config_loader"
require_relative "errors"
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
    end

    private

    def help(arguments = [])
      reject_extra_arguments!("help", arguments)

      @output.puts <<~HELP
        Mini CI

        Usage:
          mini-ci run [FILE]
          mini-ci validate [FILE]
          mini-ci list [FILE]
          mini-ci version
          mini-ci help

        Commands:
          run       Execute a pipeline
          validate  Validate a pipeline configuration
          list      Display configured pipeline steps
          version   Display the installed version
          help      Display this help message

        FILE defaults to #{ConfigLoader::DEFAULT_CONFIG_FILE}.
      HELP

      SUCCESS
    end

    def run_pipeline(arguments)
      config_path = config_path_from(arguments, "run")
      config = load_config(config_path)
      result = Pipeline.new(
        name: config.name,
        before_all: config.before_all,
        steps: config.steps,
        after_all: config.after_all,
        env: config.env,
        reporter: Reporter.new(output: @output)
      ).run

      result.success? ? SUCCESS : PIPELINE_FAILURE
    end

    def validate_pipeline(arguments)
      config_path = config_path_from(arguments, "validate")
      config = load_config(config_path)

      @output.puts "Pipeline configuration is valid."
      @output.puts
      @output.puts "Name: #{config.name}"
      @output.puts "Before-all hooks: #{config.before_all.length}"
      @output.puts "Steps: #{config.steps.length}"
      @output.puts "After-all hooks: #{config.after_all.length}"
      @output.puts "Environment variables: #{config.env.length}"
      @output.puts "Conditional items: #{conditional_item_count(config)}"
      @output.puts "File: #{config_path}"

      SUCCESS
    end

    def list_steps(arguments)
      config_path = config_path_from(arguments, "list")
      config = load_config(config_path)

      @output.puts config.name
      @output.puts

      print_global_environment(config.env)

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
