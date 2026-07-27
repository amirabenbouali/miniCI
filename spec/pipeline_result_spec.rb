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

  def categorized_result(name:, success:, exit_status:, category:)
    MiniCi::StepResult.new(
      step: step(name),
      success: success,
      exit_status: exit_status,
      duration: 0.1,
      category: category
    )
  end

  def skipped_result(name:, category: :step, skip_reason: :previous_failure)
    MiniCi::StepResult.new(
      step: step(name),
      skipped: true,
      skip_reason: skip_reason,
      duration: 0,
      category: category
    )
  end

  def retried_step_result
    MiniCi::StepResult.new(
      step: step("Retried"),
      attempts: [
        MiniCi::AttemptResult.new(attempt_number: 1, success: false, exit_status: 1, duration: 0.1),
        MiniCi::AttemptResult.new(attempt_number: 2, success: true, exit_status: 0, duration: 0.1)
      ],
      duration: 0.2
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
        step_result(name: "Two", success: false, exit_status: 1),
        skipped_result(name: "Three")
      ]
    )

    expect(result.passed_count).to eq(1)
  end

  it "counts failed steps correctly" do
    result = pipeline_result(
      configured_step_count: 2,
      step_results: [
        step_result(name: "One", success: true, exit_status: 0),
        step_result(name: "Two", success: false, exit_status: 1),
        skipped_result(name: "Three")
      ]
    )

    expect(result.failed_count).to eq(1)
  end

  it "calculates executed steps" do
    result = pipeline_result(
      configured_step_count: 3,
      step_results: [
        step_result(name: "One", success: true, exit_status: 0),
        step_result(name: "Two", success: false, exit_status: 1),
        skipped_result(name: "Three")
      ]
    )

    expect(result.executed_count).to eq(2)
  end

  it "calculates skipped steps" do
    result = pipeline_result(
      configured_step_count: 3,
      step_results: [
        step_result(name: "One", success: true, exit_status: 0),
        step_result(name: "Two", success: false, exit_status: 1),
        skipped_result(name: "Three")
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

  it "exposes the first failure result" do
    failed_step = step_result(name: "Two", success: false, exit_status: 1)
    result = pipeline_result(
      configured_step_count: 2,
      step_results: [
        step_result(name: "One", success: true, exit_status: 0),
        failed_step
      ]
    )

    expect(result.failure_result).to eq(failed_step)
  end

  it "counts total attempts" do
    result = pipeline_result(
      configured_step_count: 2,
      step_results: [
        step_result(name: "One", success: true, exit_status: 0),
        retried_step_result
      ]
    )

    expect(result.total_attempts).to eq(3)
  end

  it "counts retried steps" do
    result = pipeline_result(
      configured_step_count: 2,
      step_results: [
        step_result(name: "One", success: true, exit_status: 0),
        retried_step_result
      ]
    )

    expect(result.retried_step_count).to eq(1)
  end

  it "exposes phase-specific results" do
    setup_result = categorized_result(name: "Setup", success: true, exit_status: 0, category: :before_all)
    main_result = categorized_result(name: "Main", success: true, exit_status: 0, category: :step)
    cleanup_result = categorized_result(name: "Cleanup", success: true, exit_status: 0, category: :after_all)

    result = described_class.new(
      name: "Example",
      configured_before_all_count: 1,
      configured_step_count: 1,
      configured_after_all_count: 1,
      before_all_results: [setup_result],
      step_results: [main_result],
      after_all_results: [cleanup_result],
      total_duration: 0.3
    )

    expect(result.before_all_results).to eq([setup_result])
    expect(result.step_results).to eq([main_result])
    expect(result.after_all_results).to eq([cleanup_result])
  end

  it "keeps the normal failure as primary when cleanup also fails" do
    main_failure = categorized_result(name: "Main", success: false, exit_status: 1, category: :step)
    cleanup_failure = categorized_result(name: "Cleanup", success: false, exit_status: 2, category: :after_all)

    result = described_class.new(
      name: "Example",
      configured_step_count: 2,
      configured_after_all_count: 1,
      step_results: [main_failure],
      after_all_results: [cleanup_failure],
      total_duration: 0.3
    )

    expect(result.primary_failure).to eq(main_failure)
    expect(result.cleanup_failures).to eq([cleanup_failure])
  end

  it "uses cleanup failure as primary when main work passed" do
    cleanup_failure = categorized_result(name: "Cleanup", success: false, exit_status: 2, category: :after_all)

    result = described_class.new(
      name: "Example",
      configured_step_count: 1,
      configured_after_all_count: 1,
      step_results: [categorized_result(name: "Main", success: true, exit_status: 0, category: :step)],
      after_all_results: [cleanup_failure],
      total_duration: 0.3
    )

    expect(result).to be_failed
    expect(result.primary_failure).to eq(cleanup_failure)
  end

  it "reports setup failure as overall failure" do
    result = described_class.new(
      name: "Example",
      configured_before_all_count: 1,
      configured_step_count: 1,
      before_all_results: [categorized_result(name: "Setup", success: false, exit_status: 1, category: :before_all)],
      step_results: [skipped_result(name: "Main")],
      total_duration: 0.3
    )

    expect(result).to be_failed
    expect(result.skipped_main_step_count).to eq(1)
  end

  it "reports success when every configured phase passes" do
    result = described_class.new(
      name: "Example",
      configured_before_all_count: 1,
      configured_step_count: 1,
      configured_after_all_count: 1,
      before_all_results: [categorized_result(name: "Setup", success: true, exit_status: 0, category: :before_all)],
      step_results: [categorized_result(name: "Main", success: true, exit_status: 0, category: :step)],
      after_all_results: [categorized_result(name: "Cleanup", success: true, exit_status: 0, category: :after_all)],
      total_duration: 0.3
    )

    expect(result).to be_success
  end

  it "counts hook outcomes and cleanup failures" do
    result = described_class.new(
      name: "Example",
      configured_before_all_count: 2,
      configured_step_count: 2,
      configured_after_all_count: 2,
      before_all_results: [
        categorized_result(name: "Setup pass", success: true, exit_status: 0, category: :before_all),
        categorized_result(name: "Setup fail", success: false, exit_status: 1, category: :before_all)
      ],
      step_results: [
        skipped_result(name: "Main one"),
        skipped_result(name: "Main two")
      ],
      after_all_results: [
        categorized_result(name: "Cleanup pass", success: true, exit_status: 0, category: :after_all),
        categorized_result(name: "Cleanup fail", success: false, exit_status: 2, category: :after_all)
      ],
      total_duration: 0.3
    )

    expect(result.before_all_passed_count).to eq(1)
    expect(result.before_all_failed_count).to eq(1)
    expect(result.after_all_passed_count).to eq(1)
    expect(result.after_all_failed_count).to eq(1)
    expect(result.cleanup_failure_count).to eq(1)
    expect(result.skipped_main_step_count).to eq(2)
  end
end
