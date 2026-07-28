# frozen_string_literal: true

RSpec.describe MiniCi::CacheDefinition do
  it "defaults to saving only on success" do
    cache = described_class.new(key: "bundle", paths: ["vendor/bundle"])

    expect(cache.save_when).to eq(:success)
    expect(cache.save_on_success?).to be(true)
    expect(cache.save_on_failure?).to be(false)
  end

  it "supports saving after any executed outcome" do
    cache = described_class.new(key: "bundle", paths: ["vendor/bundle"], save_when: "always")

    expect(cache.save_on_failure?).to be(true)
  end

  it "rejects unsafe paths" do
    expect { described_class.new(key: "bundle", paths: ["../outside"]) }
      .to raise_error(ArgumentError, /stay inside/)
  end
end
