# frozen_string_literal: true

RSpec.describe "matrix result models" do
  def step
    MiniCi::Step.new(name: "Step", command: "echo step")
  end

  def pipeline_result(success:, attempts: 1, duration: 0.2)
    step_result = MiniCi::StepResult.new(
      step: step,
      success: success,
      exit_status: success ? 0 : 1,
      duration: duration
    )

    MiniCi::PipelineResult.new(
      name: "Pipeline",
      configured_step_count: 1,
      step_results: [step_result],
      total_duration: duration
    )
  end

  def job(values:, success:, attempts: 1)
    combination = MiniCi::MatrixCombination.new(values)
    MiniCi::MatrixJobResult.new(
      combination: combination,
      pipeline_result: pipeline_result(success: success, attempts: attempts),
      display_name: "Job [#{combination.label}]"
    )
  end

  it "stores job results in order" do
    jobs = [
      job(values: { "ruby" => "3.2" }, success: true),
      job(values: { "ruby" => "3.3" }, success: false)
    ]
    result = MiniCi::MatrixRunResult.new(matrix_job_results: jobs, total_duration: 0.4)

    expect(result.matrix_job_results).to eq(jobs)
  end

  it "counts passed and failed jobs" do
    result = MiniCi::MatrixRunResult.new(
      matrix_job_results: [
        job(values: { "ruby" => "3.2" }, success: true),
        job(values: { "ruby" => "3.3" }, success: false)
      ],
      total_duration: 0.4
    )

    expect(result.job_count).to eq(2)
    expect(result.passed_job_count).to eq(1)
    expect(result.failed_job_count).to eq(1)
    expect(result).to be_failed
  end

  it "reports overall success when all jobs pass" do
    result = MiniCi::MatrixRunResult.new(
      matrix_job_results: [job(values: { "ruby" => "3.2" }, success: true)],
      total_duration: 0.2
    )

    expect(result).to be_success
  end

  it "exposes failed combinations" do
    failed_job = job(values: { "ruby" => "3.3" }, success: false)

    expect(failed_job).to be_failed
    expect(failed_job.matrix_values).to eq("ruby" => "3.3")
  end
end
