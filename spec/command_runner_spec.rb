# frozen_string_literal: true

require "tempfile"

RSpec.describe MiniCi::CommandRunner do
  def temp_file
    file = Tempfile.new("mini-ci-command-runner")
    path = file.path
    file.close
    path
  end

  it "returns a structured result" do
    result = described_class.new.run("ruby -e 'exit 0'")

    expect(result).to respond_to(:success?)
    expect(result).to respond_to(:exit_status)
    expect(result).to respond_to(:duration)
  end

  it "captures exit status 0 for success" do
    result = described_class.new.run("ruby -e 'exit 0'")

    expect(result).to be_success
    expect(result.exit_status).to eq(0)
  end

  it "captures a non-zero exit status for failure" do
    result = described_class.new.run("ruby -e 'exit 7'")

    expect(result).not_to be_success
    expect(result.exit_status).to eq(7)
  end

  it "records a non-negative duration" do
    clock = [0.0, 0.05]
    runner = described_class.new(clock: -> { clock.shift || 0.05 })

    result = runner.run("ruby -e 'exit 0'")

    expect(result.duration).to be >= 0
  end

  it "makes environment variables available to the child process" do
    path = temp_file

    result = described_class.new.run(
      "ruby -e 'File.write(ARGV.fetch(0), ENV.fetch(\"APP_ENV\"))' #{path}",
      env: { "APP_ENV" => "test" }
    )

    expect(result).to be_success
    expect(File.read(path)).to eq("test")
  ensure
    FileUtils.rm_f(path) if path
  end

  it "allows provided variables to override inherited variables" do
    path = temp_file

    original = ENV["MINI_CI_OVERRIDE_TEST"]
    ENV["MINI_CI_OVERRIDE_TEST"] = "parent"

    described_class.new.run(
      "ruby -e 'File.write(ARGV.fetch(0), ENV.fetch(\"MINI_CI_OVERRIDE_TEST\"))' #{path}",
      env: { "MINI_CI_OVERRIDE_TEST" => "child" }
    )

    expect(File.read(path)).to eq("child")
  ensure
    if original.nil?
      ENV.delete("MINI_CI_OVERRIDE_TEST")
    else
      ENV["MINI_CI_OVERRIDE_TEST"] = original
    end
    FileUtils.rm_f(path) if path
  end

  it "does not mutate the parent Ruby process environment" do
    original = ENV["MINI_CI_PARENT_TEST"]

    described_class.new.run(
      "ruby -e 'exit 0'",
      env: { "MINI_CI_PARENT_TEST" => "child" }
    )

    expect(ENV["MINI_CI_PARENT_TEST"]).to eq(original)
  end

  it "preserves empty-string values" do
    path = temp_file

    described_class.new.run(
      "ruby -e 'File.write(ARGV.fetch(0), ENV.fetch(\"EMPTY_VALUE\"))' #{path}",
      env: { "EMPTY_VALUE" => "" }
    )

    expect(File.read(path)).to eq("")
  ensure
    FileUtils.rm_f(path) if path
  end
end
