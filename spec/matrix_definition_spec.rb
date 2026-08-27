# frozen_string_literal: true

RSpec.describe MiniCi::MatrixDefinition do
  subject(:definition) do
    described_class.new(
      "ruby" => ["3.2", "3.3"],
      "debug" => [true, false],
      "shard" => [1, 2]
    )
  end

  it "counts dimensions" do
    expect(definition.dimension_count).to eq(3)
  end

  it "counts combinations" do
    expect(definition.total_combination_count).to eq(8)
  end

  it "converts values to strings" do
    expect(definition.dimensions["debug"]).to eq(%w[true false])
    expect(definition.dimensions["shard"]).to eq(%w[1 2])
  end

  it "protects internal state" do
    expect { definition.dimensions["ruby"] << "3.4" }.to raise_error(FrozenError)
  end
end
