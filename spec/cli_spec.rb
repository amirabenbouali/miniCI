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
      expect(stdout).to include("Name: Mini CI Example")
      expect(stdout).to include("Steps: 3")
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
  end

  describe "list" do
    it "displays steps in order with names and commands" do
      exit_code, stdout, stderr = run_cli(["list"])

      expect(exit_code).to eq(0)
      expect(stdout).to include("Mini CI Example")
      expect(stdout).to include("1. Check Ruby version")
      expect(stdout).to include("ruby --version")
      expect(stdout).to include("2. Print message")
      expect(stdout).to include('echo "Running checks"')
      expect(stdout).to include("3. Run Bash script")
      expect(stdout).to include("bash scripts/example_check.sh")
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
      expect(stdout).to include("Mini CI Example")
      expect(stdout).to include("Pipeline summary")
      expect(stdout).to include("Status: PASSED")
      expect(stderr).to be_empty
    end

    it "returns 1 for a failed pipeline" do
      exit_code, stdout, = run_cli(["run", "examples/failing-pipeline.yml"])

      expect(exit_code).to eq(1)
      expect(stdout).to include("Status: FAILED")
      expect(stdout).to include("Skipped: 1")
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
