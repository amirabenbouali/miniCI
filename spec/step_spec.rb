# frozen_string_literal: true

RSpec.describe MiniCi::Step do
  it "stores a name and shell command" do
    step = described_class.new(
      name: "Check Ruby version",
      command: "ruby --version"
    )

    expect(step.name).to eq("Check Ruby version")
    expect(step.command).to eq("ruby --version")
  end

  it "requires a non-empty name" do
    expect do
      described_class.new(name: " ", command: "ruby --version")
    end.to raise_error(ArgumentError, "Step name must be a non-empty string")
  end

  it "requires a non-empty command" do
    expect do
      described_class.new(name: "Check Ruby version", command: "")
    end.to raise_error(ArgumentError, "Step command must be a non-empty string")
  end
end
