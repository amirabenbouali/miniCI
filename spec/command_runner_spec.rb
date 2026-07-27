# frozen_string_literal: true

require "tempfile"

RSpec.describe MiniCi::CommandRunner do
  def temp_file
    file = Tempfile.new("mini-ci-command-runner")
    path = file.path
    file.close
    path
  end

  def process_alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  rescue Errno::EPERM
    true
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

  it "lets a fast command succeed before its timeout" do
    result = described_class.new.run("ruby -e 'puts \"fast\"'", timeout: 2)

    expect(result).to be_success
    expect(result).not_to be_timed_out
    expect(result.exit_status).to eq(0)
  end

  it "times out a slow command" do
    result = described_class.new.run("ruby -e 'sleep 2'", timeout: 0.2)

    expect(result).to be_timed_out
    expect(result).not_to be_success
    expect(result.exit_status).to be_nil
  end

  it "approximately respects the configured timeout duration" do
    result = described_class.new.run("ruby -e 'sleep 2'", timeout: 0.2)

    expect(result.duration).to be >= 0.18
    expect(result.duration).to be < 2
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

  it "keeps live command output available" do
    path = temp_file

    result = described_class.new.run("ruby -e 'puts \"visible\"' > #{path}", timeout: 2)

    expect(result).to be_success
    expect(File.read(path)).to include("visible")
  ensure
    FileUtils.rm_f(path) if path
  end

  it "writes command output to injected destinations" do
    stdout = Tempfile.new("mini-ci-stdout")
    stderr = Tempfile.new("mini-ci-stderr")

    result = described_class.new(stdout: stdout, stderr: stderr).run(
      "ruby -e '$stdout.puts \"out\"; $stderr.puts \"err\"'"
    )

    stdout.rewind
    stderr.rewind
    expect(result).to be_success
    expect(stdout.read).to include("out")
    expect(stderr.read).to include("err")
  ensure
    stdout&.close!
    stderr&.close!
  end

  it "terminates child processes when the parent shell times out" do
    directory = Dir.mktmpdir
    child_pid_file = File.join(directory, "child.pid")
    command = "bash -c 'sleep 5 & echo $! > #{child_pid_file}; wait'"

    result = described_class.new.run(command, timeout: 0.2)
    child_pid = File.read(child_pid_file).to_i
    sleep 0.2

    expect(result).to be_timed_out
    expect(process_alive?(child_pid)).to be(false)
  ensure
    FileUtils.remove_entry(directory) if directory
  end

  it "reaps timed-out processes" do
    result = described_class.new.run("ruby -e 'sleep 2'", timeout: 0.2)

    expect(result).to be_timed_out
    expect { Process.wait(-1, Process::WNOHANG) }.to raise_error(Errno::ECHILD)
  end
end
