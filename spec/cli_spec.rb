# frozen_string_literal: true

require "open3"

RSpec.describe "Mini CI CLI" do
  def run_cli(config_path: nil, chdir: project_root)
    command = ["bundle", "exec", "bin/mini-ci"]
    command << config_path if config_path

    Open3.capture2e(*command, chdir: chdir)
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

  it "runs the example pipeline successfully" do
    stdout, status = run_cli

    expect(status.success?).to be(true)
    expect(stdout.force_encoding(Encoding::UTF_8)).to include("Mini CI Example")
    expect(stdout).to include("Pipeline summary")
    expect(stdout).to include("Status: PASSED")
  end

  it "loads a custom configuration path" do
    path, directory = write_temp_config(<<~YAML)
      name: Custom Pipeline
      steps:
        - name: Say hello
          run: echo hello
    YAML

    stdout, status = run_cli(config_path: path)

    expect(status.success?).to be(true)
    expect(stdout.force_encoding(Encoding::UTF_8)).to include("Custom Pipeline")
    expect(stdout).to include("Status: PASSED")
  ensure
    FileUtils.remove_entry(directory)
  end

  it "prints a clean error when the configuration file is missing" do
    _stdout, stderr, status = Open3.capture3(
      "bundle", "exec", "bin/mini-ci", "missing.yml",
      chdir: project_root
    )

    expect(status.success?).to be(false)
    expect(stderr).to include("Mini CI error: missing.yml was not found")
  end

  it "exits with a non-zero status when a step fails" do
    path, directory = write_temp_config(<<~YAML)
      name: Failing Pipeline
      steps:
        - name: Fail
          run: bash -c 'exit 1'
    YAML

    _stdout, status = run_cli(config_path: path)

    expect(status.success?).to be(false)
  ensure
    FileUtils.remove_entry(directory)
  end

  it "stops at the first failing step" do
    stdout, status = run_cli(config_path: "examples/failing-pipeline.yml")

    expect(status.success?).to be(false)
    expect(stdout).to include("Successful step")
    expect(stdout).to include("Failing step")
    expect(stdout).not_to include("Skipped step")
    expect(stdout).to include("Status: FAILED")
    expect(stdout).to include("Skipped: 1")
  end
end
