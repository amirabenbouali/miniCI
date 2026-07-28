# frozen_string_literal: true

RSpec.describe MiniCi::ArtifactDefinition do
  it "stores immutable paths" do
    paths = ["coverage/"]
    definition = described_class.new(paths: paths)
    paths << "reports/"

    expect(definition.paths).to eq(["coverage/"])
    expect(definition.paths).to be_frozen
  end

  it "defaults to always" do
    definition = described_class.new(paths: ["logs/"])

    expect(definition.when_policy).to eq(:always)
    expect(definition).to be_always
    expect(definition).to be_collect_on_success
    expect(definition).to be_collect_on_failure
  end

  it "supports success and failure policies" do
    success = described_class.new(paths: ["reports/"], when_policy: :success)
    failure = described_class.new(paths: ["logs/"], when_policy: :failure)

    expect(success).to be_collect_on_success
    expect(success).not_to be_collect_on_failure
    expect(failure).not_to be_collect_on_success
    expect(failure).to be_collect_on_failure
  end

  it "rejects unsafe paths" do
    expect { described_class.new(paths: ["../outside"]) }
      .to raise_error(ArgumentError, /inside the workspace/)
  end
end
