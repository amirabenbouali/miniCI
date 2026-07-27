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

  it "defaults retry values" do
    step = described_class.new(name: "Example", command: "echo hi")

    expect(step.retries).to eq(0)
    expect(step.retry_delay).to eq(0)
  end

  it "stores retry values" do
    step = described_class.new(name: "Example", command: "echo hi", retries: 2, retry_delay: 1.5)

    expect(step.retries).to eq(2)
    expect(step.retry_delay).to eq(1.5)
  end

  it "calculates maximum attempts" do
    step = described_class.new(name: "Example", command: "echo hi", retries: 2)

    expect(step.maximum_attempts).to eq(3)
  end

  it "rejects invalid retries" do
    expect do
      described_class.new(name: "Example", command: "echo hi", retries: -1)
    end.to raise_error(ArgumentError, "Step retries must be a non-negative integer")
  end

  it "rejects invalid retry delays" do
    expect do
      described_class.new(name: "Example", command: "echo hi", retry_delay: -1)
    end.to raise_error(ArgumentError, "Step retry_delay must be a non-negative number")
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

  it "defaults to the success policy" do
    step = described_class.new(name: "Example", command: "echo hi")

    expect(step.when_policy).to eq(:success)
    expect(step).to be_run_on_success
  end

  it "stores explicit policies" do
    step = described_class.new(name: "Example", command: "echo hi", when_policy: :failure, when_policy_explicit: true)

    expect(step.when_policy).to eq(:failure)
    expect(step).to be_run_on_failure
    expect(step).to be_when_policy_explicit
  end

  it "reports always and never helpers" do
    always_step = described_class.new(name: "Always", command: "echo hi", when_policy: :always)
    never_step = described_class.new(name: "Never", command: "echo hi", when_policy: :never)

    expect(always_step).to be_always
    expect(never_step).to be_never
  end

  it "stores a condition" do
    condition = MiniCi::ConditionParser.new.parse('env.DEPLOY == "true"')
    step = described_class.new(name: "Example", command: "echo hi", condition: condition)

    expect(step.condition).to eq(condition)
    expect(step).to be_conditional
  end

  it "rejects invalid policies" do
    expect do
      described_class.new(name: "Example", command: "echo hi", when_policy: :sometimes)
    end.to raise_error(ArgumentError, "Step when_policy must be one of success, failure, always, never")
  end
end
