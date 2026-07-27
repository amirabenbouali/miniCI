# frozen_string_literal: true

RSpec.describe MiniCi::Pipeline do
  FakeCommandResult = Struct.new(:success?, :exit_status, :duration, :timed_out?, :timeout, keyword_init: true)

  class FakeCommandRunner
    attr_reader :commands, :envs, :timeouts, :attempt_numbers

    def initialize(results)
      @results = results
      @commands = []
      @envs = []
      @timeouts = []
      @attempt_numbers = []
    end

    def run(command, env: {}, timeout: nil, attempt_number: 1)
      @commands << command
      @envs << env
      @timeouts << timeout
      @attempt_numbers << attempt_number
      @results.fetch(@commands.length - 1)
    end
  end

  class NullReporter
    def header(_name); end

    def phase_started(_name); end

    def step_started(_step, index:, total:); end

    def step_passed(_step_result); end

    def step_failed(_step_result); end

    def summary(_pipeline_result); end

    def attempt_started(_attempt_number, total:); end

    def attempt_passed(_attempt); end

    def attempt_failed(_attempt); end

    def retrying(_delay); end
  end

  class FakeSleeper
    attr_reader :delays

    def initialize
      @delays = []
    end

    def call(delay)
      @delays << delay
    end
  end

  def step(name, command, env: {}, timeout: nil, retries: 0, retry_delay: 0)
    MiniCi::Step.new(
      name: name,
      command: command,
      env: env,
      timeout: timeout,
      retries: retries,
      retry_delay: retry_delay
    )
  end

  def fake_result(success:, exit_status:, duration: 0.1, timed_out: false, timeout: nil)
    FakeCommandResult.new(success?: success, exit_status: exit_status, duration: duration, timed_out?: timed_out, timeout: timeout)
  end

  def fixed_clock
    value = -0.25
    -> { value += 0.25 }
  end

  it "returns a PipelineResult" do
    runner = FakeCommandRunner.new([
                                     fake_result(success: true, exit_status: 0)
                                   ])

    result = described_class.new(
      name: "Test Pipeline",
      steps: [step("One", "echo one")],
      command_runner: runner,
      reporter: NullReporter.new,
      clock: fixed_clock
    ).run

    expect(result).to be_a(MiniCi::PipelineResult)
  end

  it "runs steps in their defined order" do
    runner = FakeCommandRunner.new([
                                     fake_result(success: true, exit_status: 0),
                                     fake_result(success: true, exit_status: 0)
                                   ])

    described_class.new(
      name: "Test Pipeline",
      steps: [step("First", "echo first"), step("Second", "echo second")],
      command_runner: runner,
      reporter: NullReporter.new,
      clock: fixed_clock
    ).run

    expect(runner.commands).to eq(["echo first", "echo second"])
  end

  it "continues after successful steps" do
    runner = FakeCommandRunner.new([
                                     fake_result(success: true, exit_status: 0),
                                     fake_result(success: true, exit_status: 0),
                                     fake_result(success: true, exit_status: 0)
                                   ])

    described_class.new(
      name: "Test Pipeline",
      steps: [
        step("One", "echo one"),
        step("Two", "echo two"),
        step("Three", "echo three")
      ],
      command_runner: runner,
      reporter: NullReporter.new,
      clock: fixed_clock
    ).run

    expect(runner.commands).to eq(["echo one", "echo two", "echo three"])
  end

  it "stops after the first failed step" do
    runner = FakeCommandRunner.new([
                                     fake_result(success: true, exit_status: 0),
                                     fake_result(success: false, exit_status: 1),
                                     fake_result(success: true, exit_status: 0)
                                   ])

    described_class.new(
      name: "Test Pipeline",
      steps: [
        step("One", "echo one"),
        step("Two", "exit 1"),
        step("Three", "echo three")
      ],
      command_runner: runner,
      reporter: NullReporter.new,
      clock: fixed_clock
    ).run

    expect(runner.commands).to eq(["echo one", "exit 1"])
  end

  it "stores results in execution order" do
    runner = FakeCommandRunner.new([
                                     fake_result(success: true, exit_status: 0, duration: 0.1),
                                     fake_result(success: true, exit_status: 0, duration: 0.2)
                                   ])

    result = described_class.new(
      name: "Test Pipeline",
      steps: [step("First", "echo first"), step("Second", "echo second")],
      command_runner: runner,
      reporter: NullReporter.new,
      clock: fixed_clock
    ).run

    expect(result.step_results.map { |step_result| step_result.step.name }).to eq(["First", "Second"])
  end

  it "does not execute steps after a failure" do
    runner = FakeCommandRunner.new([
                                     fake_result(success: false, exit_status: 1),
                                     fake_result(success: true, exit_status: 0)
                                   ])

    described_class.new(
      name: "Test Pipeline",
      steps: [
        step("Fail", "exit 1"),
        step("Skip", "echo skipped")
      ],
      command_runner: runner,
      reporter: NullReporter.new,
      clock: fixed_clock
    ).run

    expect(runner.commands).not_to include("echo skipped")
  end

  it "calculates skipped steps correctly" do
    runner = FakeCommandRunner.new([
                                     fake_result(success: true, exit_status: 0),
                                     fake_result(success: false, exit_status: 1),
                                     fake_result(success: true, exit_status: 0)
                                   ])

    result = described_class.new(
      name: "Test Pipeline",
      steps: [
        step("One", "echo one"),
        step("Two", "exit 1"),
        step("Three", "echo three")
      ],
      command_runner: runner,
      reporter: NullReporter.new,
      clock: fixed_clock
    ).run

    expect(result.skipped_count).to eq(1)
  end

  it "records total duration" do
    runner = FakeCommandRunner.new([
                                     fake_result(success: true, exit_status: 0),
                                     fake_result(success: true, exit_status: 0)
                                   ])
    clock_values = [2.0, 3.5]

    result = described_class.new(
      name: "Test Pipeline",
      steps: [step("One", "echo one"), step("Two", "echo two")],
      command_runner: runner,
      reporter: NullReporter.new,
      clock: -> { clock_values.shift || 3.5 }
    ).run

    expect(result.total_duration).to eq(1.5)
  end

  it "reports overall success when every step succeeds" do
    runner = FakeCommandRunner.new([
                                     fake_result(success: true, exit_status: 0),
                                     fake_result(success: true, exit_status: 0)
                                   ])

    result = described_class.new(
      name: "Test Pipeline",
      steps: [
        step("One", "echo one"),
        step("Two", "echo two")
      ],
      command_runner: runner,
      reporter: NullReporter.new,
      clock: fixed_clock
    ).run

    expect(result).to be_success
  end

  it "reports overall failure when one step fails" do
    runner = FakeCommandRunner.new([
                                     fake_result(success: true, exit_status: 0),
                                     fake_result(success: false, exit_status: 2)
                                   ])

    result = described_class.new(
      name: "Test Pipeline",
      steps: [
        step("One", "echo one"),
        step("Two", "exit 2")
      ],
      command_runner: runner,
      reporter: NullReporter.new,
      clock: fixed_clock
    ).run

    expect(result).not_to be_success
  end

  it "passes global variables to every step" do
    runner = FakeCommandRunner.new([
                                     fake_result(success: true, exit_status: 0),
                                     fake_result(success: true, exit_status: 0)
                                   ])

    described_class.new(
      name: "Test Pipeline",
      steps: [step("One", "echo one"), step("Two", "echo two")],
      env: { "APP_ENV" => "test" },
      command_runner: runner,
      reporter: NullReporter.new,
      clock: fixed_clock
    ).run

    expect(runner.envs).to eq([{ "APP_ENV" => "test" }, { "APP_ENV" => "test" }])
  end

  it "passes step variables only to their own step" do
    runner = FakeCommandRunner.new([
                                     fake_result(success: true, exit_status: 0),
                                     fake_result(success: true, exit_status: 0)
                                   ])

    described_class.new(
      name: "Test Pipeline",
      steps: [
        step("One", "echo one", env: { "STEP_ONLY" => "yes" }),
        step("Two", "echo two")
      ],
      command_runner: runner,
      reporter: NullReporter.new,
      clock: fixed_clock
    ).run

    expect(runner.envs).to eq([{ "STEP_ONLY" => "yes" }, {}])
  end

  it "lets step variables override global variables" do
    runner = FakeCommandRunner.new([
                                     fake_result(success: true, exit_status: 0)
                                   ])

    described_class.new(
      name: "Test Pipeline",
      steps: [step("One", "echo one", env: { "APP_ENV" => "integration" })],
      env: { "APP_ENV" => "test" },
      command_runner: runner,
      reporter: NullReporter.new,
      clock: fixed_clock
    ).run

    expect(runner.envs.first).to eq("APP_ENV" => "integration")
  end

  it "does not leak environments from one step into another" do
    runner = FakeCommandRunner.new([
                                     fake_result(success: true, exit_status: 0),
                                     fake_result(success: true, exit_status: 0)
                                   ])

    described_class.new(
      name: "Test Pipeline",
      steps: [
        step("One", "echo one", env: { "FEATURE_FLAG" => "enabled" }),
        step("Two", "echo two")
      ],
      env: { "APP_ENV" => "test" },
      command_runner: runner,
      reporter: NullReporter.new,
      clock: fixed_clock
    ).run

    expect(runner.envs).to eq([
                                { "APP_ENV" => "test", "FEATURE_FLAG" => "enabled" },
                                { "APP_ENV" => "test" }
                              ])
  end

  it "does not mutate the original environment hashes" do
    global_env = { "APP_ENV" => "test" }
    step_env = { "APP_ENV" => "integration" }
    runner = FakeCommandRunner.new([
                                     fake_result(success: true, exit_status: 0)
                                   ])

    described_class.new(
      name: "Test Pipeline",
      steps: [step("One", "echo one", env: step_env)],
      env: global_env,
      command_runner: runner,
      reporter: NullReporter.new,
      clock: fixed_clock
    ).run

    expect(global_env).to eq("APP_ENV" => "test")
    expect(step_env).to eq("APP_ENV" => "integration")
  end

  it "passes step timeouts to the command runner" do
    runner = FakeCommandRunner.new([
                                     fake_result(success: true, exit_status: 0)
                                   ])

    described_class.new(
      name: "Test Pipeline",
      steps: [step("One", "echo one", timeout: 2.5)],
      command_runner: runner,
      reporter: NullReporter.new,
      clock: fixed_clock
    ).run

    expect(runner.timeouts).to eq([2.5])
  end

  it "fails the pipeline when a step times out" do
    runner = FakeCommandRunner.new([
                                     fake_result(success: false, exit_status: nil, timed_out: true, timeout: 1)
                                   ])

    result = described_class.new(
      name: "Test Pipeline",
      steps: [step("Timeout", "sleep 10", timeout: 1)],
      command_runner: runner,
      reporter: NullReporter.new,
      clock: fixed_clock
    ).run

    expect(result).not_to be_success
  end

  it "does not execute steps after a timeout" do
    runner = FakeCommandRunner.new([
                                     fake_result(success: false, exit_status: nil, timed_out: true, timeout: 1),
                                     fake_result(success: true, exit_status: 0)
                                   ])

    described_class.new(
      name: "Test Pipeline",
      steps: [
        step("Timeout", "sleep 10", timeout: 1),
        step("Skip", "echo skipped")
      ],
      command_runner: runner,
      reporter: NullReporter.new,
      clock: fixed_clock
    ).run

    expect(runner.commands).to eq(["sleep 10"])
  end

  it "preserves timeout results" do
    runner = FakeCommandRunner.new([
                                     fake_result(success: false, exit_status: nil, duration: 1.01, timed_out: true, timeout: 1)
                                   ])

    result = described_class.new(
      name: "Test Pipeline",
      steps: [step("Timeout", "sleep 10", timeout: 1)],
      command_runner: runner,
      reporter: NullReporter.new,
      clock: fixed_clock
    ).run

    expect(result.step_results.first).to be_timed_out
    expect(result.step_results.first.timeout).to eq(1)
  end

  it "does not retry after a successful first attempt" do
    sleeper = FakeSleeper.new
    runner = FakeCommandRunner.new([
                                     fake_result(success: true, exit_status: 0)
                                   ])

    described_class.new(
      name: "Test Pipeline",
      steps: [step("Flaky", "echo ok", retries: 2, retry_delay: 1)],
      command_runner: runner,
      reporter: NullReporter.new,
      sleeper: sleeper,
      clock: fixed_clock
    ).run

    expect(runner.commands.length).to eq(1)
    expect(sleeper.delays).to eq([])
  end

  it "continues when a failure is followed by a successful retry" do
    runner = FakeCommandRunner.new([
                                     fake_result(success: false, exit_status: 1),
                                     fake_result(success: true, exit_status: 0),
                                     fake_result(success: true, exit_status: 0)
                                   ])

    result = described_class.new(
      name: "Test Pipeline",
      steps: [
        step("Flaky", "bash flaky", retries: 2),
        step("Next", "echo next")
      ],
      command_runner: runner,
      reporter: NullReporter.new,
      clock: fixed_clock
    ).run

    expect(result).to be_success
    expect(runner.commands).to eq(["bash flaky", "bash flaky", "echo next"])
  end

  it "stops when all attempts fail" do
    runner = FakeCommandRunner.new([
                                     fake_result(success: false, exit_status: 1),
                                     fake_result(success: false, exit_status: 1),
                                     fake_result(success: true, exit_status: 0)
                                   ])

    described_class.new(
      name: "Test Pipeline",
      steps: [
        step("Flaky", "bash flaky", retries: 1),
        step("Skip", "echo skipped")
      ],
      command_runner: runner,
      reporter: NullReporter.new,
      clock: fixed_clock
    ).run

    expect(runner.commands).to eq(["bash flaky", "bash flaky"])
  end

  it "records the correct number of attempts" do
    runner = FakeCommandRunner.new([
                                     fake_result(success: false, exit_status: 1),
                                     fake_result(success: true, exit_status: 0)
                                   ])

    result = described_class.new(
      name: "Test Pipeline",
      steps: [step("Flaky", "bash flaky", retries: 1)],
      command_runner: runner,
      reporter: NullReporter.new,
      clock: fixed_clock
    ).run

    expect(result.step_results.first.attempt_count).to eq(2)
    expect(runner.attempt_numbers).to eq([1, 2])
  end

  it "retries timed-out attempts when retries remain" do
    runner = FakeCommandRunner.new([
                                     fake_result(success: false, exit_status: nil, timed_out: true, timeout: 1),
                                     fake_result(success: true, exit_status: 0)
                                   ])

    result = described_class.new(
      name: "Test Pipeline",
      steps: [step("Timeout once", "sleep 10", timeout: 1, retries: 1)],
      command_runner: runner,
      reporter: NullReporter.new,
      clock: fixed_clock
    ).run

    expect(result).to be_success
    expect(result.step_results.first.attempts.first).to be_timed_out
  end

  it "sleeps only between eligible attempts" do
    sleeper = FakeSleeper.new
    runner = FakeCommandRunner.new([
                                     fake_result(success: false, exit_status: 1),
                                     fake_result(success: false, exit_status: 1),
                                     fake_result(success: false, exit_status: 1)
                                   ])

    described_class.new(
      name: "Test Pipeline",
      steps: [step("Flaky", "bash flaky", retries: 2, retry_delay: 0.5)],
      command_runner: runner,
      reporter: NullReporter.new,
      sleeper: sleeper,
      clock: fixed_clock
    ).run

    expect(sleeper.delays).to eq([0.5, 0.5])
  end

  it "does not sleep after a successful retry" do
    sleeper = FakeSleeper.new
    runner = FakeCommandRunner.new([
                                     fake_result(success: false, exit_status: 1),
                                     fake_result(success: true, exit_status: 0)
                                   ])

    described_class.new(
      name: "Test Pipeline",
      steps: [step("Flaky", "bash flaky", retries: 2, retry_delay: 0.5)],
      command_runner: runner,
      reporter: NullReporter.new,
      sleeper: sleeper,
      clock: fixed_clock
    ).run

    expect(sleeper.delays).to eq([0.5])
  end

  it "passes environments and timeouts to every attempt" do
    runner = FakeCommandRunner.new([
                                     fake_result(success: false, exit_status: 1),
                                     fake_result(success: true, exit_status: 0)
                                   ])

    described_class.new(
      name: "Test Pipeline",
      steps: [step("Flaky", "bash flaky", env: { "STEP" => "yes" }, timeout: 2, retries: 1)],
      env: { "GLOBAL" => "yes" },
      command_runner: runner,
      reporter: NullReporter.new,
      clock: fixed_clock
    ).run

    expect(runner.envs).to eq([
                                { "GLOBAL" => "yes", "STEP" => "yes" },
                                { "GLOBAL" => "yes", "STEP" => "yes" }
                              ])
    expect(runner.timeouts).to eq([2, 2])
  end

  it "runs setup hooks before main steps and cleanup hooks after them" do
    runner = FakeCommandRunner.new([
                                     fake_result(success: true, exit_status: 0),
                                     fake_result(success: true, exit_status: 0),
                                     fake_result(success: true, exit_status: 0)
                                   ])

    result = described_class.new(
      name: "Hooks",
      before_all: [step("Prepare", "prepare")],
      steps: [step("Main", "main")],
      after_all: [step("Cleanup", "cleanup")],
      command_runner: runner,
      reporter: NullReporter.new,
      clock: fixed_clock
    ).run

    expect(runner.commands).to eq(["prepare", "main", "cleanup"])
    expect(result.before_all_results.first).to be_before_all
    expect(result.step_results.first).to be_normal_step
    expect(result.after_all_results.first).to be_after_all
  end

  it "runs cleanup after main-step failure and skips remaining main steps" do
    runner = FakeCommandRunner.new([
                                     fake_result(success: true, exit_status: 0),
                                     fake_result(success: false, exit_status: 1),
                                     fake_result(success: true, exit_status: 0)
                                   ])

    result = described_class.new(
      name: "Hooks",
      steps: [
        step("Pass", "pass"),
        step("Fail", "fail"),
        step("Skip", "skip")
      ],
      after_all: [step("Cleanup", "cleanup")],
      command_runner: runner,
      reporter: NullReporter.new,
      clock: fixed_clock
    ).run

    expect(runner.commands).to eq(["pass", "fail", "cleanup"])
    expect(result.skipped_main_step_count).to eq(1)
    expect(result.primary_failure.step.name).to eq("Fail")
  end

  it "runs cleanup after setup failure and skips all main steps" do
    runner = FakeCommandRunner.new([
                                     fake_result(success: false, exit_status: 1),
                                     fake_result(success: true, exit_status: 0)
                                   ])

    result = described_class.new(
      name: "Hooks",
      before_all: [
        step("Prepare", "prepare"),
        step("Skip setup", "skip-setup")
      ],
      steps: [step("Skip main", "skip-main")],
      after_all: [step("Cleanup", "cleanup")],
      command_runner: runner,
      reporter: NullReporter.new,
      clock: fixed_clock
    ).run

    expect(runner.commands).to eq(["prepare", "cleanup"])
    expect(result.skipped_main_step_count).to eq(1)
    expect(result.primary_failure.step.name).to eq("Prepare")
  end

  it "continues running cleanup hooks after a cleanup failure" do
    runner = FakeCommandRunner.new([
                                     fake_result(success: true, exit_status: 0),
                                     fake_result(success: false, exit_status: 2),
                                     fake_result(success: true, exit_status: 0)
                                   ])

    result = described_class.new(
      name: "Hooks",
      steps: [step("Main", "main")],
      after_all: [
        step("Fail cleanup", "cleanup-fail"),
        step("Final cleanup", "cleanup-final")
      ],
      command_runner: runner,
      reporter: NullReporter.new,
      clock: fixed_clock
    ).run

    expect(runner.commands).to eq(["main", "cleanup-fail", "cleanup-final"])
    expect(result).to be_failed
    expect(result.cleanup_failures.map { |failure| failure.step.name }).to eq(["Fail cleanup"])
  end

  it "applies retries and timeouts to hooks" do
    runner = FakeCommandRunner.new([
                                     fake_result(success: false, exit_status: nil, timed_out: true, timeout: 1),
                                     fake_result(success: true, exit_status: 0),
                                     fake_result(success: true, exit_status: 0)
                                   ])

    result = described_class.new(
      name: "Hooks",
      before_all: [step("Prepare", "prepare", timeout: 1, retries: 1)],
      steps: [step("Main", "main")],
      command_runner: runner,
      reporter: NullReporter.new,
      clock: fixed_clock
    ).run

    expect(result).to be_success
    expect(runner.commands).to eq(["prepare", "prepare", "main"])
    expect(runner.timeouts).to eq([1, 1, nil])
  end

  it "passes environments to hooks" do
    runner = FakeCommandRunner.new([
                                     fake_result(success: true, exit_status: 0),
                                     fake_result(success: true, exit_status: 0)
                                   ])

    described_class.new(
      name: "Hooks",
      before_all: [step("Prepare", "prepare", env: { "PHASE" => "setup" })],
      steps: [step("Main", "main")],
      env: { "GLOBAL" => "yes" },
      command_runner: runner,
      reporter: NullReporter.new,
      clock: fixed_clock
    ).run

    expect(runner.envs).to eq([
                                { "GLOBAL" => "yes", "PHASE" => "setup" },
                                { "GLOBAL" => "yes" }
                              ])
  end
end
