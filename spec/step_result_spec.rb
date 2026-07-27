# frozen_string_literal: true

RSpec.describe MiniCi::StepResult do
  def step
    MiniCi::Step.new(name: "Example", command: "echo hi")
  end

  def attempt(number, success:, exit_status:, duration:, timed_out: false)
    MiniCi::AttemptResult.new(
      attempt_number: number,
      success: success,
      exit_status: exit_status,
      duration: duration,
      timed_out: timed_out,
      timeout: timed_out ? 1 : nil
    )
  end

  it "reports success for a successful result" do
    result = described_class.new(step: step, success: true, exit_status: 0, duration: 0.1)

    expect(result).to be_success
    expect(result).not_to be_failed
  end

  it "reports failure for a failed result" do
    result = described_class.new(step: step, success: false, exit_status: 1, duration: 0.1)

    expect(result).to be_failed
    expect(result).not_to be_success
  end

  it "stores the exit status" do
    result = described_class.new(step: step, success: false, exit_status: 7, duration: 0.1)

    expect(result.exit_status).to eq(7)
  end

  it "stores the duration" do
    result = described_class.new(step: step, success: true, exit_status: 0, duration: 0.42)

    expect(result.duration).to eq(0.42)
  end

  it "reports timeout results" do
    result = described_class.new(
      step: step,
      success: false,
      exit_status: nil,
      duration: 1.01,
      timed_out: true,
      timeout: 1
    )

    expect(result).to be_timed_out
    expect(result).not_to be_success
    expect(result.timeout).to eq(1)
  end

  it "stores attempts in order" do
    attempts = [
      attempt(1, success: false, exit_status: 1, duration: 0.1),
      attempt(2, success: true, exit_status: 0, duration: 0.2)
    ]

    result = described_class.new(step: step, attempts: attempts, duration: 0.3)

    expect(result.attempts.map(&:attempt_number)).to eq([1, 2])
  end

  it "returns the final attempt" do
    final = attempt(2, success: true, exit_status: 0, duration: 0.2)
    result = described_class.new(
      step: step,
      attempts: [attempt(1, success: false, exit_status: 1, duration: 0.1), final],
      duration: 0.3
    )

    expect(result.final_attempt).to eq(final)
  end

  it "counts attempts and reports whether it retried" do
    result = described_class.new(
      step: step,
      attempts: [
        attempt(1, success: false, exit_status: 1, duration: 0.1),
        attempt(2, success: true, exit_status: 0, duration: 0.2)
      ],
      duration: 0.3
    )

    expect(result.attempt_count).to eq(2)
    expect(result).to be_retried
  end

  it "succeeds when a later attempt succeeds" do
    result = described_class.new(
      step: step,
      attempts: [
        attempt(1, success: false, exit_status: 1, duration: 0.1),
        attempt(2, success: true, exit_status: 0, duration: 0.2)
      ],
      duration: 0.3
    )

    expect(result).to be_success
  end

  it "fails when every attempt fails" do
    result = described_class.new(
      step: step,
      attempts: [
        attempt(1, success: false, exit_status: 1, duration: 0.1),
        attempt(2, success: false, exit_status: 1, duration: 0.2)
      ],
      duration: 0.3
    )

    expect(result).to be_failed
  end

  it "preserves timeout information from the final attempt" do
    result = described_class.new(
      step: step,
      attempts: [attempt(1, success: false, exit_status: nil, duration: 1.0, timed_out: true)],
      duration: 1.0
    )

    expect(result).to be_timed_out
  end

  it "calculates overall duration from attempts when no explicit duration is supplied" do
    result = described_class.new(
      step: step,
      attempts: [
        attempt(1, success: false, exit_status: 1, duration: 0.1),
        attempt(2, success: true, exit_status: 0, duration: 0.2)
      ]
    )

    expect(result.total_duration).to be_within(0.0001).of(0.3)
  end

  it "defaults to a normal step category" do
    result = described_class.new(step: step, success: true, exit_status: 0, duration: 0.1)

    expect(result.category).to eq(:step)
    expect(result).to be_normal_step
  end

  it "reports setup and cleanup categories" do
    setup_result = described_class.new(step: step, success: true, exit_status: 0, duration: 0.1, category: :before_all)
    cleanup_result = described_class.new(step: step, success: true, exit_status: 0, duration: 0.1, category: :after_all)

    expect(setup_result).to be_before_all
    expect(cleanup_result).to be_after_all
  end

  it "rejects unknown categories" do
    expect do
      described_class.new(step: step, success: true, exit_status: 0, duration: 0.1, category: :deploy)
    end.to raise_error(ArgumentError, "Step result category must be :before_all, :step, or :after_all")
  end
end
