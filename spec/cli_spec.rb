# frozen_string_literal: true

require "stringio"

RSpec.describe MiniCi::CLI do
  def run_cli(arguments, chdir: project_root)
    output = StringIO.new
    error_output = StringIO.new
    exit_code = nil

    Dir.chdir(chdir) do
      exit_code = described_class.new(
        arguments: arguments,
        output: output,
        error_output: error_output
      ).call
    end

    [exit_code, output.string.force_encoding(Encoding::UTF_8), error_output.string]
  end

  def project_root
    File.expand_path("..", __dir__)
  end

  def write_temp_config(content)
    directory = Dir.mktmpdir
    path = File.join(directory, "custom-pipeline.yml")
    File.write(path, content)
    [path, directory]
  end

  describe "general behaviour" do
    it "displays help when no arguments are provided" do
      exit_code, stdout, stderr = run_cli([])

      expect(exit_code).to eq(0)
      expect(stdout).to include("Usage:")
      expect(stderr).to be_empty
    end

    it "displays help for help" do
      exit_code, stdout, = run_cli(["help"])

      expect(exit_code).to eq(0)
      expect(stdout).to include("mini-ci run [FILE]")
    end

    it "displays help for --help" do
      exit_code, stdout, = run_cli(["--help"])

      expect(exit_code).to eq(0)
      expect(stdout).to include("Commands:")
    end

    it "displays help for -h" do
      exit_code, stdout, = run_cli(["-h"])

      expect(exit_code).to eq(0)
      expect(stdout).to include("FILE defaults to pipeline.yml.")
    end

    it "returns a usage error for an unknown command" do
      exit_code, stdout, stderr = run_cli(["deploy"])

      expect(exit_code).to eq(2)
      expect(stdout).to be_empty
      expect(stderr).to include('Mini CI error: unknown command "deploy"')
      expect(stderr).to include("Run `mini-ci help` for usage information.")
    end

    it "prints errors to stderr" do
      exit_code, stdout, stderr = run_cli(["validate", "missing.yml"])

      expect(exit_code).to eq(2)
      expect(stdout).to be_empty
      expect(stderr).to include("Mini CI error: missing.yml was not found")
    end
  end

  describe "version" do
    it "displays MiniCi::VERSION" do
      exit_code, stdout, stderr = run_cli(["version"])

      expect(exit_code).to eq(0)
      expect(stdout).to include("Mini CI #{MiniCi::VERSION}")
      expect(stderr).to be_empty
    end

    it "rejects extra arguments" do
      exit_code, stdout, stderr = run_cli(["version", "extra"])

      expect(exit_code).to eq(2)
      expect(stdout).to be_empty
      expect(stderr).to include("Mini CI error: version does not accept extra arguments")
    end
  end

  describe "validate" do
    it "returns success for the default configuration" do
      exit_code, stdout, stderr = run_cli(["validate"])

      expect(exit_code).to eq(0)
      expect(stdout).to include("Pipeline configuration is valid.")
      expect(stdout).to include("Name: Environment Example")
      expect(stdout).to include("Before-all hooks: 0")
      expect(stdout).to include("Steps: 2")
      expect(stdout).to include("After-all hooks: 0")
      expect(stdout).to include("Environment variables: 3")
      expect(stdout).to include("File: pipeline.yml")
      expect(stderr).to be_empty
    end

    it "returns success for a valid custom configuration" do
      path, directory = write_temp_config(<<~YAML)
        name: Custom Pipeline
        steps:
          - name: Say hello
            run: echo hello
      YAML

      exit_code, stdout, = run_cli(["validate", path])

      expect(exit_code).to eq(0)
      expect(stdout).to include("Name: Custom Pipeline")
      expect(stdout).to include("Steps: 1")
      expect(stdout).to include("Environment variables: 0")
      expect(stdout).to include("File: #{path}")
    ensure
      FileUtils.remove_entry(directory) if directory
    end

    it "returns a non-zero exit code for invalid configuration" do
      path, directory = write_temp_config(<<~YAML)
        name: Invalid
      YAML

      exit_code, stdout, stderr = run_cli(["validate", path])

      expect(exit_code).to eq(2)
      expect(stdout).to be_empty
      expect(stderr).to include('Mini CI error: Invalid pipeline configuration: missing "steps"')
    ensure
      FileUtils.remove_entry(directory) if directory
    end

    it "does not execute pipeline steps" do
      directory = Dir.mktmpdir
      marker = File.join(directory, "marker.txt")
      path = File.join(directory, "pipeline.yml")
      File.write(path, <<~YAML)
        name: Validate Only
        steps:
          - name: Create marker
            run: ruby -e 'File.write("#{marker}", "created")'
      YAML

      exit_code, = run_cli(["validate", path])

      expect(exit_code).to eq(0)
      expect(File.exist?(marker)).to be(false)
    ensure
      FileUtils.remove_entry(directory) if directory
    end

    it "displays hook counts" do
      exit_code, stdout, stderr = run_cli(["validate", "examples/hooks-success-pipeline.yml"])

      expect(exit_code).to eq(0)
      expect(stdout).to include("Before-all hooks: 1")
      expect(stdout).to include("Steps: 2")
      expect(stdout).to include("After-all hooks: 1")
      expect(stderr).to be_empty
    end

    it "does not execute hooks" do
      directory = Dir.mktmpdir
      marker = File.join(directory, "hook-marker.txt")
      path = File.join(directory, "pipeline.yml")
      File.write(path, <<~YAML)
        name: Validate Hooks Only
        before_all:
          - name: Create setup marker
            run: ruby -e 'File.write("#{marker}", "setup")'
        steps:
          - name: Step
            run: echo step
        after_all:
          - name: Create cleanup marker
            run: ruby -e 'File.write("#{marker}", "cleanup")'
      YAML

      exit_code, = run_cli(["validate", path])

      expect(exit_code).to eq(0)
      expect(File.exist?(marker)).to be(false)
    ensure
      FileUtils.remove_entry(directory) if directory
    end

    it "accepts valid environment configuration" do
      path, directory = write_temp_config(<<~YAML)
        name: Env Pipeline
        env:
          APP_ENV: test
        steps:
          - name: Step
            run: echo hi
            env:
              APP_ENV: integration
      YAML

      exit_code, stdout, stderr = run_cli(["validate", path])

      expect(exit_code).to eq(0)
      expect(stdout).to include("Name: Env Pipeline")
      expect(stdout).to include("Environment variables: 1")
      expect(stderr).to be_empty
    ensure
      FileUtils.remove_entry(directory) if directory
    end

    it "rejects invalid environment configuration" do
      path, directory = write_temp_config(<<~YAML)
        name: Invalid Env
        env:
          APP-NAME: test
        steps:
          - name: Step
            run: echo hi
      YAML

      exit_code, stdout, stderr = run_cli(["validate", path])

      expect(exit_code).to eq(2)
      expect(stdout).to be_empty
      expect(stderr).to include("Mini CI error: Invalid pipeline configuration:")
      expect(stderr).to include("APP-NAME")
    ensure
      FileUtils.remove_entry(directory) if directory
    end

    it "accepts valid timeout configuration" do
      path, directory = write_temp_config(<<~YAML)
        name: Timeout Validate
        steps:
          - name: Slow
            run: sleep 1
            timeout: 0.5
      YAML

      exit_code, stdout, stderr = run_cli(["validate", path])

      expect(exit_code).to eq(0)
      expect(stdout).to include("Pipeline configuration is valid.")
      expect(stderr).to be_empty
    ensure
      FileUtils.remove_entry(directory) if directory
    end

    it "rejects invalid timeout configuration" do
      path, directory = write_temp_config(<<~YAML)
        name: Invalid Timeout
        steps:
          - name: Slow
            run: sleep 1
            timeout: "1"
      YAML

      exit_code, stdout, stderr = run_cli(["validate", path])

      expect(exit_code).to eq(2)
      expect(stdout).to be_empty
      expect(stderr).to include("timeout must be a positive number")
    ensure
      FileUtils.remove_entry(directory) if directory
    end

    it "accepts valid retry fields" do
      path, directory = write_temp_config(<<~YAML)
        name: Retry Validate
        steps:
          - name: Flaky
            run: echo hi
            retries: 2
            retry_delay: 0.5
      YAML

      exit_code, stdout, stderr = run_cli(["validate", path])

      expect(exit_code).to eq(0)
      expect(stdout).to include("Pipeline configuration is valid.")
      expect(stderr).to be_empty
    ensure
      FileUtils.remove_entry(directory) if directory
    end

    it "rejects invalid retry fields" do
      path, directory = write_temp_config(<<~YAML)
        name: Invalid Retry
        steps:
          - name: Flaky
            run: echo hi
            retries: 1.5
      YAML

      exit_code, stdout, stderr = run_cli(["validate", path])

      expect(exit_code).to eq(2)
      expect(stdout).to be_empty
      expect(stderr).to include("retries must be a non-negative integer")
    ensure
      FileUtils.remove_entry(directory) if directory
    end
  end

  describe "list" do
    it "displays steps in order with names and commands" do
      exit_code, stdout, stderr = run_cli(["list"])

      expect(exit_code).to eq(0)
      expect(stdout).to include("Environment Example")
      expect(stdout).to include("1. Print global variables")
      expect(stdout).to include("bash scripts/print_env.sh")
      expect(stdout).to include("2. Override one variable")
      expect(stdout).to include('ruby -e')
      expect(stderr).to be_empty
    end

    it "displays global variables" do
      _exit_code, stdout, = run_cli(["list"])

      expect(stdout).to include("Global environment:")
      expect(stdout).to include("APP_ENV=test")
      expect(stdout).to include("LOG_LEVEL=info")
      expect(stdout).to include("SHARED_VALUE=global")
    end

    it "displays step-specific variables" do
      _exit_code, stdout, = run_cli(["list"])

      expect(stdout).to include("Environment:")
      expect(stdout).to include("SHARED_VALUE=step")
      expect(stdout).to include("FEATURE_FLAG=enabled")
    end

    it "displays configured timeout values" do
      exit_code, stdout, stderr = run_cli(["list", "examples/timeout-pipeline.yml"])

      expect(exit_code).to eq(0)
      expect(stdout).to include("Slow step")
      expect(stdout).to include("Timeout: 1s")
      expect(stderr).to be_empty
    end

    it "displays retry settings" do
      exit_code, stdout, stderr = run_cli(["list", "examples/retry-pipeline.yml"])

      expect(exit_code).to eq(0)
      expect(stdout).to include("Flaky check")
      expect(stdout).to include("Retries: 2")
      expect(stdout).to include("Retry delay: 0.10s")
      expect(stderr).to be_empty
    end

    it "displays each phase" do
      exit_code, stdout, stderr = run_cli(["list", "examples/hooks-success-pipeline.yml"])

      expect(exit_code).to eq(0)
      expect(stdout).to include("Before all:")
      expect(stdout).to include("1. Prepare workspace")
      expect(stdout).to include("Steps:")
      expect(stdout).to include("1. Check marker exists")
      expect(stdout).to include("After all:")
      expect(stdout).to include("1. Clean workspace")
      expect(stderr).to be_empty
    end

    it "accepts a custom configuration file" do
      path, directory = write_temp_config(<<~YAML)
        name: Custom List
        steps:
          - name: First
            run: echo first
      YAML

      exit_code, stdout, = run_cli(["list", path])

      expect(exit_code).to eq(0)
      expect(stdout).to include("Custom List")
      expect(stdout).to include("1. First")
      expect(stdout).to include("echo first")
    ensure
      FileUtils.remove_entry(directory) if directory
    end

    it "does not execute pipeline steps" do
      directory = Dir.mktmpdir
      marker = File.join(directory, "marker.txt")
      path = File.join(directory, "pipeline.yml")
      File.write(path, <<~YAML)
        name: List Only
        steps:
          - name: Create marker
            run: ruby -e 'File.write("#{marker}", "created")'
      YAML

      exit_code, = run_cli(["list", path])

      expect(exit_code).to eq(0)
      expect(File.exist?(marker)).to be(false)
    ensure
      FileUtils.remove_entry(directory) if directory
    end
  end

  describe "run" do
    it "executes a successful pipeline" do
      exit_code, stdout, stderr = run_cli(["run"])

      expect(exit_code).to eq(0)
      expect(stdout).to include("Environment Example")
      expect(stdout).to include("Pipeline summary")
      expect(stdout).to include("Status: PASSED")
      expect(stderr).to be_empty
    end

    it "returns 1 for a failed pipeline" do
      exit_code, stdout, = run_cli(["run", "examples/failing-pipeline.yml"])

      expect(exit_code).to eq(1)
      expect(stdout).to include("Status: FAILED")
      expect(stdout).to include("Skipped main steps: 1")
    end

    it "accepts a custom configuration file" do
      path, directory = write_temp_config(<<~YAML)
        name: Custom Run
        steps:
          - name: Say hello
            run: echo hello
      YAML

      exit_code, stdout, = run_cli(["run", path])

      expect(exit_code).to eq(0)
      expect(stdout).to include("Custom Run")
      expect(stdout).to include("Status: PASSED")
    ensure
      FileUtils.remove_entry(directory) if directory
    end

    it "passes configured variables to commands" do
      directory = Dir.mktmpdir
      marker = File.join(directory, "env.txt")
      path = File.join(directory, "pipeline.yml")
      File.write(path, <<~YAML)
        name: Env Run
        env:
          APP_ENV: test
        steps:
          - name: Write env
            run: ruby -e 'File.write("#{marker}", ENV.fetch("APP_ENV"))'
      YAML

      exit_code, = run_cli(["run", path])

      expect(exit_code).to eq(0)
      expect(File.read(marker)).to eq("test")
    ensure
      FileUtils.remove_entry(directory) if directory
    end

    it "returns 1 for a timeout pipeline" do
      exit_code, stdout, = run_cli(["run", "examples/timeout-pipeline.yml"])

      expect(exit_code).to eq(1)
      expect(stdout.downcase).to include("timed out")
      expect(stdout).to include("Skipped main steps: 1")
      expect(stdout).not_to include("Never reached")
    end

    it "returns 0 for a retry-success pipeline" do
      exit_code, stdout, stderr = run_cli(["run", "examples/retry-pipeline.yml"])

      expect(exit_code).to eq(0)
      expect(stdout).to include("Attempt 1/3")
      expect(stdout).to include("Attempt 2/3")
      expect(stdout).to include("Status: PASSED")
      expect(stderr).to be_empty
    end

    it "returns 1 for a retry-failure pipeline" do
      exit_code, stdout, = run_cli(["run", "examples/retry-failure-pipeline.yml"])

      expect(exit_code).to eq(1)
      expect(stdout).to include("Step failed after 3 attempts")
      expect(stdout).to include("Status: FAILED")
      expect(stdout).not_to include("this should be skipped")
    end

    it "returns 0 for the successful hook example" do
      exit_code, stdout, stderr = run_cli(["run", "examples/hooks-success-pipeline.yml"])

      expect(exit_code).to eq(0)
      expect(stdout).to include("Setup")
      expect(stdout).to include("Pipeline")
      expect(stdout).to include("Cleanup")
      expect(stdout).to include("Status: PASSED")
      expect(stderr).to be_empty
    end

    it "returns 1 for the main-failure hook example and still runs cleanup" do
      exit_code, stdout, = run_cli(["run", "examples/hooks-main-failure-pipeline.yml"])

      expect(exit_code).to eq(1)
      expect(stdout).to include("Failing main step")
      expect(stdout).to include("Clean workspace")
      expect(stdout).not_to include("This should not run")
      expect(stdout).to include("Skipped main steps: 1")
    end

    it "returns 1 for the cleanup-failure hook example and keeps cleaning up" do
      exit_code, stdout, = run_cli(["run", "examples/hooks-cleanup-failure-pipeline.yml"])

      expect(exit_code).to eq(1)
      expect(stdout).to include("Failing cleanup hook")
      expect(stdout).to include("Cleanup still runs")
      expect(stdout).to include("Cleanup failures:")
    end
  end

  describe "argument validation" do
    it "rejects more than one file argument" do
      exit_code, stdout, stderr = run_cli(["run", "first.yml", "second.yml"])

      expect(exit_code).to eq(2)
      expect(stdout).to be_empty
      expect(stderr).to include("Mini CI error: run accepts at most one file argument")
    end

    it "rejects extra help arguments" do
      exit_code, stdout, stderr = run_cli(["help", "extra"])

      expect(exit_code).to eq(2)
      expect(stdout).to be_empty
      expect(stderr).to include("Mini CI error: help does not accept extra arguments")
    end
  end
end
