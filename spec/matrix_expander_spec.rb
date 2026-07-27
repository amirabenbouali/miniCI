# frozen_string_literal: true

RSpec.describe MiniCi::MatrixExpander do
  subject(:expander) { described_class.new }

  def definition(dimensions)
    MiniCi::MatrixDefinition.new(dimensions)
  end

  it "expands one dimension" do
    combinations = expander.expand(definition("ruby" => ["3.2", "3.3"]))

    expect(combinations.map(&:values)).to eq([
                                               { "ruby" => "3.2" },
                                               { "ruby" => "3.3" }
                                             ])
  end

  it "expands two dimensions in deterministic order" do
    combinations = expander.expand(definition("ruby" => ["3.2", "3.3"], "db" => ["sqlite", "postgres"]))

    expect(combinations.map(&:values)).to eq([
                                               { "ruby" => "3.2", "db" => "sqlite" },
                                               { "ruby" => "3.2", "db" => "postgres" },
                                               { "ruby" => "3.3", "db" => "sqlite" },
                                               { "ruby" => "3.3", "db" => "postgres" }
                                             ])
  end

  it "expands three dimensions" do
    combinations = expander.expand(definition("ruby" => ["3.3"], "db" => ["sqlite"], "os" => ["linux", "macos"]))

    expect(combinations.map(&:label)).to eq([
                                              "ruby=3.3, db=sqlite, os=linux",
                                              "ruby=3.3, db=sqlite, os=macos"
                                            ])
  end

  it "exposes matrix environment variables" do
    combination = expander.expand(definition("ruby" => ["3.3"], "feature_flag" => [true])).first

    expect(combination.environment).to eq(
      "MATRIX_RUBY" => "3.3",
      "MATRIX_FEATURE_FLAG" => "true"
    )
  end

  it "rejects empty dimensions" do
    expect { expander.expand(definition({})) }.to raise_error(ArgumentError, "Matrix must contain at least one dimension")
  end

  it "enforces the expansion limit" do
    large = definition("a" => (1..17).to_a, "b" => (1..17).to_a)

    expect { expander.expand(large) }.to raise_error(ArgumentError, /exceeding the limit/)
  end
end
