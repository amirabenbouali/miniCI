# frozen_string_literal: true

RSpec.describe MiniCi::PipelineResult do
  def step(name)
    MiniCi::Step.new(name: name, command: "echo #{name}")
  end

  def step_result(name:, success:, exit_status:)
    MiniCi::StepResult.new(
      step: step(name),
      success: success,
      exit_status: exit_status,
      duration: 0.1
    )
  end

  def pipeline_result(configured_step_count:, step_results:)
    described_class.new(
      name: "Example",
      configured_step_count: configured_step_count,
      step_results: step_results,
      total_duration: 0.3
    )
  end

  it "counts passed steps correctly" do
    result = pipeline_result(
      configured_step_count: 2,
      step_results: [
        step_result(name: "One", success: true, exit_status: 0),
        step_result(name: "Two", success: false, exit_status: 1)
      ]
    )

    expect(result.passed_count).to eq(1)
  end

  it "counts failed steps correctly" do
    result = pipeline_result(
      configured_step_count: 2,
      step_results: [
        step_result(name: "One", success: true, exit_status: 0),
        step_result(name: "Two", success: false, exit_status: 1)
      ]
    )

    expect(result.failed_count).to eq(1)
  end

  it "calculates executed steps" do
    result = pipeline_result(
      configured_step_count: 3,
      step_results: [
        step_result(name: "One", success: true, exit_status: 0),
        step_result(name: "Two", success: false, exit_status: 1)
      ]
    )

    expect(result.executed_count).to eq(2)
  end

  it "calculates skipped steps" do
    result = pipeline_result(
      configured_step_count: 3,
      step_results: [
        step_result(name: "One", success: true, exit_status: 0),
        step_result(name: "Two", success: false, exit_status: 1)
      ]
    )

    expect(result.skipped_count).to eq(1)
  end

  it "reports overall success when all configured steps ran and passed" do
    result = pipeline_result(
      configured_step_count: 2,
      step_results: [
        step_result(name: "One", success: true, exit_status: 0),
        step_result(name: "Two", success: true, exit_status: 0)
      ]
    )

    expect(result).to be_success
    expect(result).not_to be_failed
  end

  it "reports overall failure when a step failed" do
    result = pipeline_result(
      configured_step_count: 2,
      step_results: [
        step_result(name: "One", success: true, exit_status: 0),
        step_result(name: "Two", success: false, exit_status: 1)
      ]
    )

    expect(result).to be_failed
    expect(result).not_to be_success
  end
end
