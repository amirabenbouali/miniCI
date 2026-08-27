# frozen_string_literal: true

require "stringio"
require "json"

RSpec.describe "Mini CI plugin CLI" do
  def run_cli(arguments)
    output = StringIO.new
    error_output = StringIO.new
    exit_code = MiniCi::CLI.new(arguments: arguments, output: output, error_output: error_output).call
    [exit_code, output.string, error_output.string]
  end

  around do |example|
    MiniCi::Plugin.reset!
    example.run
  ensure
    MiniCi::Plugin.reset!
  end

  it "lists explicit plugins" do
    exit_code, stdout, stderr = run_cli(["plugins", "list", "--plugin", "examples/plugins/message_item.rb"])

    expect(exit_code).to eq(0)
    expect(stdout).to include("message-plugin 1.0.0")
    expect(stdout).to include("Item types: message")
    expect(stderr).to be_empty
  end

  it "validates explicit plugins without executing a pipeline" do
    exit_code, stdout, stderr = run_cli(["plugins", "validate", "--plugin", "examples/plugins/run_logger.rb",
                                         "--plugin", "examples/plugins/message_item.rb"])

    expect(exit_code).to eq(0)
    expect(stdout).to include("Plugin validation passed.")
    expect(stdout).to include("Custom item types: 1")
    expect(stderr).to be_empty
  end

  it "runs a pipeline with a plugin-defined item" do
    exit_code, stdout, stderr = run_cli(["run", "examples/plugin-basic-pipeline.yml", "--plugin",
                                         "examples/plugins/message_item.rb"])

    expect(exit_code).to eq(0)
    expect(stdout).to include("Hello from a plugin")
    expect(stderr).to be_empty
  end

  it "loads validators during validate but does not run runtime callbacks" do
    FileUtils.rm_f("tmp/plugin-output/run-log.json")

    exit_code, stdout, stderr = run_cli(["validate", "examples/plugin-basic-pipeline.yml", "--plugin",
                                         "examples/plugins/run_logger.rb", "--plugin", "examples/plugins/message_item.rb"])

    expect(exit_code).to eq(0)
    expect(stdout).to include("Plugins loaded: 2")
    expect(File.exist?("tmp/plugin-output/run-log.json")).to be(false)
    expect(stderr).to be_empty
  end

  it "returns a configuration error for plugin validator failures" do
    exit_code, stdout, stderr = run_cli(["validate", "examples/plugin-validation-failure-pipeline.yml", "--plugin",
                                         "examples/plugins/policy_validator.rb"])

    expect(exit_code).to eq(2)
    expect(stdout).to be_empty
    expect(stderr).to include("Plugin validation failed [policy-validator]")
  end

  it "returns non-zero for callback failures after preserving command output" do
    exit_code, stdout, stderr = run_cli(["run", "examples/plugin-callback-failure-pipeline.yml", "--plugin",
                                         "examples/plugins/callback_failure.rb"])

    expect(exit_code).to eq(1)
    expect(stdout).to include("[1/1] Successful command before callback failure")
    expect(stdout).to include("Status: PASSED")
    expect(stdout).to include("Pipeline execution: PASSED")
    expect(stdout).to include("- callback-failure during after_run: intentional callback failure")
    expect(stdout).to include("Overall status: FAILED")
    expect(stderr).to be_empty
  end

  it "keeps command failures primary when after_run also fails" do
    exit_code, stdout, stderr = run_cli(["run", "examples/failing-pipeline.yml", "--plugin",
                                         "examples/plugins/callback_failure.rb"])

    expect(exit_code).to eq(1)
    expect(stdout).to include("Primary failure:")
    expect(stdout).to include("Failing step failed with exit code 1")
    expect(stdout).to include("Pipeline execution: FAILED")
    expect(stdout).to include("- callback-failure during after_run: intentional callback failure")
    expect(stdout).to include("Overall status: FAILED")
    expect(stderr).to be_empty
  end

  it "writes failed manifest status for after_run plugin failures" do
    directory = Dir.mktmpdir

    exit_code, _stdout, _stderr = run_cli([
                                            "run",
                                            "examples/plugin-callback-failure-pipeline.yml",
                                            "--plugin",
                                            "examples/plugins/callback_failure.rb",
                                            "--artifacts-dir",
                                            directory
                                          ])
    manifest_path = Dir.glob(File.join(directory, "*", "manifest.json")).first
    manifest = JSON.parse(File.read(manifest_path))

    expect(exit_code).to eq(1)
    expect(manifest["status"]).to eq("failed")
    expect(manifest["plugin_failures"].first["plugin"]).to eq("callback-failure")
  ensure
    FileUtils.remove_entry(directory) if directory
  end

  it "returns a clean error for incompatible plugin API versions" do
    exit_code, stdout, stderr = run_cli(["plugins", "validate", "--plugin", "examples/plugins/incompatible_api.rb"])

    expect(exit_code).to eq(2)
    expect(stdout).to be_empty
    expect(stderr).to include("requires API version 2")
  end
end
