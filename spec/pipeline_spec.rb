# frozen_string_literal: true

RSpec.describe MiniCi::Pipeline do
  FakeCommandResult = Struct.new(:success?, :exit_status, :duration, keyword_init: true)

  class FakeCommandRunner
    attr_reader :commands, :envs

    def initialize(results)
      @results = results
      @commands = []
      @envs = []
    end

    def run(command, env: {})
      @commands << command
      @envs << env
      @results.fetch(@commands.length - 1)
    end
  end

  class NullReporter
    def header(_name); end

    def step_started(_step, index:, total:); end

    def step_passed(_step_result); end

    def step_failed(_step_result); end

    def summary(_pipeline_result); end
  end

  def step(name, command, env: {})
    MiniCi::Step.new(name: name, command: command, env: env)
  end

  def fake_result(success:, exit_status:, duration: 0.1)
    FakeCommandResult.new(success?: success, exit_status: exit_status, duration: duration)
  end

  def fixed_clock
    values = [0.0, 0.25, 0.50, 0.75, 1.00]
    -> { values.shift || values.last }
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
end
