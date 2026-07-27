# frozen_string_literal: true

RSpec.describe MiniCi::MatrixRunner do
  FakeMatrixCommandResult = Struct.new(:success?, :exit_status, :duration, :timed_out?, :timeout, keyword_init: true)

  class FakeMatrixCommandRunner
    attr_reader :commands, :envs

    def initialize(results)
      @results = results
      @commands = []
      @envs = []
    end

    def run(command, env: {}, timeout: nil, attempt_number: 1)
      @commands << command
      @envs << env
      @results.fetch(@commands.length - 1)
    end
  end

  class NullMatrixReporter
    def method_missing(*) end
  end

  def result(success:, exit_status: nil)
    FakeMatrixCommandResult.new(
      success?: success,
      exit_status: exit_status || (success ? 0 : 1),
      duration: 0.1,
      timed_out?: false,
      timeout: nil
    )
  end

  def step(name, command, env: {}, condition: nil)
    MiniCi::Step.new(name: name, command: command, env: env, condition: condition)
  end

  def condition(expression)
    MiniCi::ConditionParser.new.parse(expression)
  end

  def matrix
    MiniCi::MatrixDefinition.new(
      "ruby" => ["3.2", "3.3"],
      "database" => ["sqlite", "postgres"]
    )
  end

  def runner_with(command_runner:, steps:, before_all: [], after_all: [], env: {})
    described_class.new(
      name: "Matrix",
      matrix_definition: matrix,
      before_all: before_all,
      steps: steps,
      after_all: after_all,
      env: env,
      command_runner: command_runner,
      reporter: NullMatrixReporter.new,
      clock: -> { 1.0 }
    )
  end

  it "runs one pipeline execution per combination in order" do
    command_runner = FakeMatrixCommandRunner.new(Array.new(4) { result(success: true) })

    matrix_result = runner_with(
      command_runner: command_runner,
      steps: [step("Show", "show")]
    ).run

    expect(matrix_result.job_count).to eq(4)
    expect(command_runner.envs.map { |env| [env["MATRIX_RUBY"], env["MATRIX_DATABASE"]] }).to eq([
                                                                                                    ["3.2", "sqlite"],
                                                                                                    ["3.2", "postgres"],
                                                                                                    ["3.3", "sqlite"],
                                                                                                    ["3.3", "postgres"]
                                                                                                  ])
  end

  it "continues later jobs after one job fails" do
    command_runner = FakeMatrixCommandRunner.new([
                                                  result(success: true),
                                                  result(success: false),
                                                  result(success: true),
                                                  result(success: true)
                                                ])

    matrix_result = runner_with(
      command_runner: command_runner,
      steps: [step("Check", "check")]
    ).run

    expect(command_runner.commands).to eq(["check", "check", "check", "check"])
    expect(matrix_result).to be_failed
    expect(matrix_result.failed_job_count).to eq(1)
  end

  it "runs cleanup for failed jobs" do
    command_runner = FakeMatrixCommandRunner.new([
                                                  result(success: false),
                                                  result(success: true),
                                                  result(success: true),
                                                  result(success: true),
                                                  result(success: true),
                                                  result(success: true),
                                                  result(success: true),
                                                  result(success: true)
                                                ])

    runner_with(
      command_runner: command_runner,
      steps: [step("Check", "check")],
      after_all: [step("Cleanup", "cleanup")]
    ).run

    expect(command_runner.commands.first(2)).to eq(["check", "cleanup"])
  end

  it "makes matrix values available to setup, steps, cleanup, and conditions" do
    command_runner = FakeMatrixCommandRunner.new(Array.new(14) { result(success: true) })

    runner_with(
      command_runner: command_runner,
      before_all: [step("Setup", "setup")],
      steps: [
        step("Step", "step"),
        step("Postgres only", "postgres", condition: condition('env.MATRIX_DATABASE == "postgres"'))
      ],
      after_all: [step("Cleanup", "cleanup")]
    ).run

    expect(command_runner.commands).to eq([
                                           "setup", "step", "cleanup",
                                           "setup", "step", "postgres", "cleanup",
                                           "setup", "step", "cleanup",
                                           "setup", "step", "postgres", "cleanup"
                                         ])
  end

  it "applies environment precedence without leaking between jobs" do
    command_runner = FakeMatrixCommandRunner.new(Array.new(4) { result(success: true) })

    runner_with(
      command_runner: command_runner,
      env: { "MATRIX_RUBY" => "pipeline", "APP_ENV" => "test" },
      steps: [step("Override", "override", env: { "MATRIX_RUBY" => "step" })]
    ).run

    expect(command_runner.envs.map { |env| env["MATRIX_RUBY"] }).to eq(["step", "step", "step", "step"])
    expect(command_runner.envs.map { |env| env["APP_ENV"] }.uniq).to eq(["test"])
    expect(command_runner.envs.map { |env| env["MATRIX_DATABASE"] }).to eq(["sqlite", "postgres", "sqlite", "postgres"])
  end

  it "does not mutate global ENV" do
    before = ENV.to_h
    command_runner = FakeMatrixCommandRunner.new(Array.new(4) { result(success: true) })

    runner_with(
      command_runner: command_runner,
      steps: [step("Show", "show")]
    ).run

    expect(ENV.to_h).to eq(before)
  end

  it "includes the pipeline name in matrix job display names when explicitly provided" do
    command_runner = FakeMatrixCommandRunner.new(Array.new(4) { result(success: true) })

    matrix_result = runner_with(
      command_runner: command_runner,
      steps: [step("Show", "show")]
    ).run

    expect(matrix_result.matrix_job_results.first.display_name).to eq("Matrix [ruby=3.2, database=sqlite]")
  end

  it "uses matrix-only display names when the pipeline name was omitted" do
    command_runner = FakeMatrixCommandRunner.new(Array.new(4) { result(success: true) })

    matrix_result = described_class.new(
      name: "Mini CI",
      name_explicit: false,
      matrix_definition: matrix,
      before_all: [],
      steps: [step("Show", "show")],
      after_all: [],
      command_runner: command_runner,
      reporter: NullMatrixReporter.new,
      clock: -> { 1.0 }
    ).run

    expect(matrix_result.matrix_job_results.first.display_name).to eq("ruby=3.2, database=sqlite")
  end
end
