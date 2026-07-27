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

  it "defaults environment to empty" do
    step = described_class.new(name: "Example", command: "echo hi")

    expect(step.env).to eq({})
  end

  it "defaults timeout to nil" do
    step = described_class.new(name: "Example", command: "echo hi")

    expect(step.timeout).to be_nil
  end

  it "stores a valid timeout" do
    step = described_class.new(name: "Example", command: "echo hi", timeout: 2.5)

    expect(step.timeout).to eq(2.5)
  end

  it "rejects invalid timeouts" do
    expect do
      described_class.new(name: "Example", command: "echo hi", timeout: 0)
    end.to raise_error(ArgumentError, "Step timeout must be a positive number")
  end

  it "stores environment variables" do
    step = described_class.new(
      name: "Example",
      command: "echo hi",
      env: { "APP_ENV" => "test" }
    )

    expect(step.env).to eq("APP_ENV" => "test")
  end

  it "does not allow caller mutation to alter the internal environment" do
    env = { "APP_ENV" => "test" }
    step = described_class.new(name: "Example", command: "echo hi", env: env)

    env["APP_ENV"] = "development"

    expect(step.env).to eq("APP_ENV" => "test")
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
