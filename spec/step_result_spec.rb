# frozen_string_literal: true

RSpec.describe MiniCi::StepResult do
  def step
    MiniCi::Step.new(name: "Example", command: "echo hi")
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
end
