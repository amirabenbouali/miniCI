# frozen_string_literal: true

RSpec.describe MiniCi::Dashboard::Configuration do
  it "uses local defaults" do
    config = described_class.new

    expect(config.host).to eq("127.0.0.1")
    expect(config.port).to eq(4567)
    expect(config.max_runs).to eq(200)
    expect(config.non_loopback?).to be(false)
  end

  it "flags non-loopback hosts" do
    expect(described_class.new(host: "0.0.0.0").non_loopback?).to be(true)
  end

  it "rejects invalid ports and retention values" do
    expect { described_class.new(port: 70_000) }.to raise_error(MiniCi::UsageError)
    expect { described_class.new(max_runs: 0) }.to raise_error(MiniCi::UsageError)
  end
end
