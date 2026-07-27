# frozen_string_literal: true

RSpec.describe MiniCi::AttemptResult do
  it "reports success" do
    result = described_class.new(attempt_number: 1, success: true, exit_status: 0, duration: 0.1)

    expect(result).to be_success
    expect(result).not_to be_failed
  end

  it "reports normal failure" do
    result = described_class.new(attempt_number: 1, success: false, exit_status: 1, duration: 0.1)

    expect(result).to be_failed
    expect(result).not_to be_timed_out
  end

  it "reports timeout" do
    result = described_class.new(
      attempt_number: 2,
      success: false,
      exit_status: nil,
      duration: 1.0,
      timed_out: true,
      timeout: 1
    )

    expect(result).to be_timed_out
    expect(result).not_to be_success
  end

  it "stores duration and attempt number" do
    result = described_class.new(attempt_number: 3, success: true, exit_status: 0, duration: 0.25)

    expect(result.attempt_number).to eq(3)
    expect(result.duration).to eq(0.25)
  end
end
