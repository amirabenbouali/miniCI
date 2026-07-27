# frozen_string_literal: true

require "stringio"

RSpec.describe MiniCi::Reporter do
  def step(name: "Example", command: "echo hi")
    MiniCi::Step.new(name: name, command: command)
  end

  def step_result(success:, exit_status:, duration:, name: "Example", category: :step)
    MiniCi::StepResult.new(
      step: step(name: name),
      success: success,
      exit_status: exit_status,
      duration: duration,
      category: category
    )
  end

  def timeout_step_result
    MiniCi::StepResult.new(
      step: step(name: "Integration tests"),
      success: false,
      exit_status: nil,
      duration: 2.14,
      timed_out: true,
      timeout: 2
    )
  end

  def attempt(number, success:, exit_status:, duration:, timed_out: false)
    MiniCi::AttemptResult.new(
      attempt_number: number,
      success: success,
      exit_status: exit_status,
      duration: duration,
      timed_out: timed_out,
      timeout: timed_out ? 2 : nil
    )
  end

  def pipeline_result(
    step_results:,
    configured_step_count:,
    total_duration:,
    before_all_results: [],
    after_all_results: [],
    configured_before_all_count: 0,
    configured_after_all_count: 0
  )
    MiniCi::PipelineResult.new(
      name: "Example Pipeline",
      configured_before_all_count: configured_before_all_count,
      configured_step_count: configured_step_count,
      configured_after_all_count: configured_after_all_count,
      before_all_results: before_all_results,
      step_results: step_results,
      after_all_results: after_all_results,
      total_duration: total_duration
    )
  end

  def reporter_with(output)
    described_class.new(output: output)
  end

  it "prints the pipeline header" do
    output = StringIO.new
    reporter_with(output).header("Mini CI Example")

    expect(output.string).to include("Mini CI")
    expect(output.string).to include("Mini CI Example")
  end

  it "prints a passed step with duration" do
    output = StringIO.new

    reporter_with(output).step_passed(step_result(success: true, exit_status: 0, duration: 0.08))

    expect(output.string).to include("Passed")
    expect(output.string).to include("0.08s")
  end

  it "prints a failed step with exit status and duration" do
    output = StringIO.new

    reporter_with(output).step_failed(step_result(success: false, exit_status: 1, duration: 1.42))

    expect(output.string).to include("Failed with exit code 1")
    expect(output.string).to include("1.42s")
  end

  it "prints a timed-out step with its timeout duration" do
    output = StringIO.new

    reporter_with(output).step_failed(timeout_step_result)

    expect(output.string.downcase).to include("timed out")
    expect(output.string).to include("2.00s")
  end

  it "prints attempt numbers" do
    output = StringIO.new

    reporter_with(output).attempt_started(1, total: 3)

    expect(output.string).to include("Attempt 1/3")
  end

  it "prints retry delay" do
    output = StringIO.new

    reporter_with(output).retrying(1)

    expect(output.string).to include("Retrying in 1.00s")
  end

  it "prints eventual success for a retried attempt" do
    output = StringIO.new

    reporter_with(output).attempt_passed(attempt(2, success: true, exit_status: 0, duration: 0.18))

    expect(output.string).to include("Passed")
    expect(output.string).to include("0.18s")
  end

  it "prints timeout retry attempts" do
    output = StringIO.new

    reporter_with(output).attempt_failed(attempt(2, success: false, exit_status: nil, duration: 2, timed_out: true))

    expect(output.string.downcase).to include("timed out")
    expect(output.string).to include("2.00s")
  end

  it "prints exhausted retry details" do
    output = StringIO.new
    result = MiniCi::StepResult.new(
      step: step(name: "Flaky"),
      attempts: [
        attempt(1, success: false, exit_status: 1, duration: 0.1),
        attempt(2, success: false, exit_status: 1, duration: 0.1)
      ],
      duration: 0.2
    )

    reporter_with(output).step_failed(result)

    expect(output.string).to include("Step failed after 2 attempts")
  end

  it "prints a successful pipeline summary" do
    output = StringIO.new
    result = pipeline_result(
      step_results: [
        step_result(success: true, exit_status: 0, duration: 0.08),
        step_result(success: true, exit_status: 0, duration: 0.01)
      ],
      configured_step_count: 2,
      total_duration: 0.09
    )

    reporter_with(output).summary(result)

    text = output.string
    expect(text).to include("Pipeline summary")
    expect(text).to include("Status: PASSED")
    expect(text).to include("2 passed")
    expect(text).to include("0 failed")
    expect(text).to include("2 total")
    expect(text).to include("Duration: 0.09s")
    expect(text).to include("Attempts: 2")
  end

  it "prints skipped count when the pipeline fails before all steps run" do
    output = StringIO.new
    result = pipeline_result(
      step_results: [
        step_result(success: true, exit_status: 0, duration: 0.08),
        step_result(success: false, exit_status: 1, duration: 1.42)
      ],
      configured_step_count: 3,
      total_duration: 1.50
    )

    reporter_with(output).summary(result)

    text = output.string
    expect(text).to include("Status: FAILED")
    expect(text).to include("1 passed")
    expect(text).to include("1 failed")
    expect(text).to include("3 configured")
    expect(text).to include("Skipped main steps: 1")
    expect(text).to include("Duration: 1.50s")
    expect(text).to include("Attempts: 2")
  end

  it "prints timeout failure details in the summary" do
    output = StringIO.new
    result = pipeline_result(
      step_results: [
        step_result(success: true, exit_status: 0, duration: 0.08),
        timeout_step_result
      ],
      configured_step_count: 3,
      total_duration: 2.20
    )

    reporter_with(output).summary(result)

    text = output.string
    expect(text).to include("Status: FAILED")
    expect(text).to include("Skipped main steps: 1")
    expect(text.downcase).to include("timed out")
    expect(text).to include("Primary failure:")
    expect(text).to include("Integration tests timed out")
  end

  it "prints retried step count in the summary" do
    output = StringIO.new
    result = pipeline_result(
      step_results: [
        MiniCi::StepResult.new(
          step: step(name: "Flaky"),
          attempts: [
            attempt(1, success: false, exit_status: 1, duration: 0.1),
            attempt(2, success: true, exit_status: 0, duration: 0.1)
          ],
          duration: 0.2
        )
      ],
      configured_step_count: 1,
      total_duration: 0.2
    )

    reporter_with(output).summary(result)

    expect(output.string).to include("Retried steps: 1")
    expect(output.string).to include("Attempts: 2")
  end

  it "prints phase headings" do
    output = StringIO.new

    reporter_with(output).phase_started("Setup")
    reporter_with(output).phase_started("Pipeline")
    reporter_with(output).phase_started("Cleanup")

    expect(output.string).to include("Setup")
    expect(output.string).to include("Pipeline")
    expect(output.string).to include("Cleanup")
  end

  it "prints setup and cleanup counts in the summary" do
    output = StringIO.new
    result = pipeline_result(
      before_all_results: [
        step_result(success: true, exit_status: 0, duration: 0.1, name: "Prepare", category: :before_all)
      ],
      step_results: [
        step_result(success: true, exit_status: 0, duration: 0.1, name: "Main")
      ],
      after_all_results: [
        step_result(success: false, exit_status: 2, duration: 0.1, name: "Cleanup", category: :after_all)
      ],
      configured_before_all_count: 1,
      configured_step_count: 1,
      configured_after_all_count: 1,
      total_duration: 0.3
    )

    reporter_with(output).summary(result)

    expect(output.string).to include("Setup hooks: 1 passed, 0 failed")
    expect(output.string).to include("Cleanup hooks: 0 passed, 1 failed")
  end

  it "prints primary and cleanup failures" do
    output = StringIO.new
    result = pipeline_result(
      step_results: [
        step_result(success: false, exit_status: 1, duration: 0.1, name: "Run tests")
      ],
      after_all_results: [
        step_result(success: false, exit_status: 2, duration: 0.1, name: "Remove temporary files", category: :after_all)
      ],
      configured_step_count: 2,
      configured_after_all_count: 1,
      total_duration: 0.2
    )

    reporter_with(output).summary(result)

    expect(output.string).to include("Primary failure:")
    expect(output.string).to include("Run tests failed with exit code 1")
    expect(output.string).to include("Cleanup failures:")
    expect(output.string).to include("Remove temporary files failed with exit code 2")
  end
end
