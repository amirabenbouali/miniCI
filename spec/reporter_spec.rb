# frozen_string_literal: true

require "stringio"

RSpec.describe MiniCi::Reporter do
  def step(name: "Example", command: "echo hi")
    MiniCi::Step.new(name: name, command: command)
  end

  def step_result(success:, exit_status:, duration:)
    MiniCi::StepResult.new(
      step: step,
      success: success,
      exit_status: exit_status,
      duration: duration
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

  def pipeline_result(step_results:, configured_step_count:, total_duration:)
    MiniCi::PipelineResult.new(
      name: "Example Pipeline",
      configured_step_count: configured_step_count,
      step_results: step_results,
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
    expect(text).to include("Skipped: 1")
    expect(text).to include("Duration: 1.50s")
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
    expect(text).to include("Skipped: 1")
    expect(text.downcase).to include("timed out")
    expect(text).to include("Failure: Integration tests timed out")
  end
end
