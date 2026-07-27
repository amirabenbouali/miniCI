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
        steps: config.steps,
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
      @output.puts "Steps: #{config.steps.length}"
      @output.puts "Environment variables: #{config.env.length}"
      @output.puts "File: #{config_path}"

      SUCCESS
    end

    def list_steps(arguments)
      config_path = config_path_from(arguments, "list")
      config = load_config(config_path)

      @output.puts config.name
      @output.puts

      print_global_environment(config.env)

      config.steps.each_with_index do |step, index|
        @output.puts "#{index + 1}. #{step.name}"
        @output.puts "   #{step.command}"
        print_step_environment(step.env)
        @output.puts
      end

      SUCCESS
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

      @output.puts "   Environment:"
      env.each do |name, value|
        @output.puts "     #{name}=#{value}"
      end
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
