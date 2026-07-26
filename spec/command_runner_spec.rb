# frozen_string_literal: true

RSpec.describe MiniCi::CommandRunner do
  it "returns a structured result" do
    result = described_class.new.run("ruby -e 'exit 0'")

    expect(result).to respond_to(:success?)
    expect(result).to respond_to(:exit_status)
    expect(result).to respond_to(:duration)
  end

  it "captures exit status 0 for success" do
    result = described_class.new.run("ruby -e 'exit 0'")

    expect(result).to be_success
    expect(result.exit_status).to eq(0)
  end

  it "captures a non-zero exit status for failure" do
    result = described_class.new.run("ruby -e 'exit 7'")

    expect(result).not_to be_success
    expect(result.exit_status).to eq(7)
  end

  it "records a non-negative duration" do
    clock = [0.0, 0.05]
    runner = described_class.new(clock: -> { clock.shift || 0.05 })

    result = runner.run("ruby -e 'exit 0'")

    expect(result.duration).to be >= 0
  end
end
