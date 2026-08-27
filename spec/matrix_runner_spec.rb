# frozen_string_literal: true

RSpec.describe MiniCi::MatrixRunner do
  FakeMatrixCommandResult = Struct.new(:success?, :exit_status, :duration, :timed_out?, :timeout, keyword_init: true)

  class FakeMatrixCommandRunner
    attr_reader :commands, :envs

    def initialize(results)
      @results = results
      @commands = []
      @envs = []
      @mutex = Mutex.new
      @index = 0
    end

    def run(command, env: {}, timeout: nil, attempt_number: 1)
      @mutex.synchronize do
        @commands << command
        @envs << env
        result = @results.fetch(@index)
        @index += 1
        result
      end
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
      "database" => %w[sqlite postgres]
    )
  end

  def runner_with(command_runner:, steps:, before_all: [], after_all: [], env: {}, concurrency: 1)
    described_class.new(
      name: "Matrix",
      matrix_definition: matrix,
      before_all: before_all,
      steps: steps,
      after_all: after_all,
      env: env,
      concurrency: MiniCi::ConcurrencyConfig.new(concurrency),
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

    expect(command_runner.commands).to eq(%w[check check check check])
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

    expect(command_runner.commands.first(2)).to eq(%w[check cleanup])
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

    expect(command_runner.commands).to eq(%w[
                                            setup step cleanup
                                            setup step postgres cleanup
                                            setup step cleanup
                                            setup step postgres cleanup
                                          ])
  end

  it "applies environment precedence without leaking between jobs" do
    command_runner = FakeMatrixCommandRunner.new(Array.new(4) { result(success: true) })

    runner_with(
      command_runner: command_runner,
      env: { "MATRIX_RUBY" => "pipeline", "APP_ENV" => "test" },
      steps: [step("Override", "override", env: { "MATRIX_RUBY" => "step" })]
    ).run

    expect(command_runner.envs.map { |env| env["MATRIX_RUBY"] }).to eq(%w[step step step step])
    expect(command_runner.envs.map { |env| env["APP_ENV"] }.uniq).to eq(["test"])
    expect(command_runner.envs.map { |env| env["MATRIX_DATABASE"] }).to eq(%w[sqlite postgres sqlite postgres])
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
      concurrency: MiniCi::ConcurrencyConfig.new(1),
      command_runner: command_runner,
      reporter: NullMatrixReporter.new,
      clock: -> { 1.0 }
    ).run

    expect(matrix_result.matrix_job_results.first.display_name).to eq("ruby=3.2, database=sqlite")
  end

  it "caps actual worker count by job count" do
    command_runner = FakeMatrixCommandRunner.new([result(success: true)])
    one_job_matrix = MiniCi::MatrixDefinition.new("ruby" => ["3.2"])

    matrix_result = described_class.new(
      name: "Matrix",
      matrix_definition: one_job_matrix,
      before_all: [],
      steps: [step("Show", "show")],
      after_all: [],
      concurrency: MiniCi::ConcurrencyConfig.new(4),
      command_runner: command_runner,
      reporter: NullMatrixReporter.new
    ).run

    expect(matrix_result.requested_concurrency).to eq(4)
    expect(matrix_result.actual_worker_count).to eq(1)
  end

  it "runs jobs concurrently when concurrency allows it" do
    started = Queue.new
    release = Queue.new

    blocking_runner_class = Class.new do
      define_method(:run) do |_command, env: {}, timeout: nil, attempt_number: 1|
        started << env.fetch("MATRIX_DATABASE")
        release.pop
        FakeMatrixCommandResult.new(success?: true, exit_status: 0, duration: 0.1, timed_out?: false, timeout: nil)
      end
    end

    runner = described_class.new(
      name: "Matrix",
      matrix_definition: matrix,
      before_all: [],
      steps: [step("Show", "show")],
      after_all: [],
      concurrency: MiniCi::ConcurrencyConfig.new(2),
      command_runner_factory: ->(_buffer) { blocking_runner_class.new },
      reporter: NullMatrixReporter.new
    )

    run_thread = Thread.new { runner.run }

    first_started = started.pop
    second_started = started.pop
    expect([first_started, second_started]).to contain_exactly("sqlite", "postgres")

    4.times { release << true }
    matrix_result = run_thread.value

    expect(matrix_result.actual_worker_count).to eq(2)
    expect(matrix_result.job_count).to eq(4)
  end

  it "preserves result order even when jobs finish out of order" do
    release = Queue.new

    finishing_runner_class = Class.new do
      define_method(:run) do |_command, env: {}, timeout: nil, attempt_number: 1|
        release.pop if env.fetch("MATRIX_DATABASE") == "sqlite"
        FakeMatrixCommandResult.new(success?: true, exit_status: 0, duration: 0.1, timed_out?: false, timeout: nil)
      end
    end

    runner = described_class.new(
      name: "Matrix",
      matrix_definition: matrix,
      before_all: [],
      steps: [step("Show", "show")],
      after_all: [],
      concurrency: MiniCi::ConcurrencyConfig.new(2),
      command_runner_factory: ->(_buffer) { finishing_runner_class.new },
      reporter: NullMatrixReporter.new
    )

    run_thread = Thread.new { runner.run }
    sleep 0.05
    2.times { release << true }
    matrix_result = run_thread.value

    expect(matrix_result.matrix_job_results.map { |job| job.combination.label }).to eq([
                                                                                         "ruby=3.2, database=sqlite",
                                                                                         "ruby=3.2, database=postgres",
                                                                                         "ruby=3.3, database=sqlite",
                                                                                         "ruby=3.3, database=postgres"
                                                                                       ])
  end

  it "captures internal worker exceptions" do
    runner = described_class.new(
      name: "Matrix",
      matrix_definition: matrix,
      before_all: [],
      steps: [step("Show", "show")],
      after_all: [],
      concurrency: MiniCi::ConcurrencyConfig.new(2),
      command_runner_factory: ->(_buffer) { raise "broken runner" },
      reporter: NullMatrixReporter.new
    )

    expect { runner.run }
      .to raise_error(MiniCi::InternalError, /broken runner/)
  end
end
