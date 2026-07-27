# frozen_string_literal: true

RSpec.describe MiniCi::ConditionParser do
  subject(:parser) { described_class.new }

  it "parses equality with double quotes" do
    condition = parser.parse('env.DEPLOY == "true"')

    expect(condition.variable_name).to eq("DEPLOY")
    expect(condition.operator).to eq("==")
    expect(condition.expected_value).to eq("true")
  end

  it "parses inequality with double quotes" do
    condition = parser.parse('env.APP_ENV != "production"')

    expect(condition.variable_name).to eq("APP_ENV")
    expect(condition.operator).to eq("!=")
    expect(condition.expected_value).to eq("production")
  end

  it "parses single-quoted values" do
    condition = parser.parse("env.BRANCH == 'main'")

    expect(condition.expected_value).to eq("main")
  end

  it "allows surrounding whitespace" do
    condition = parser.parse('  env.DEPLOY   ==   "true"  ')

    expect(condition.source).to eq('env.DEPLOY   ==   "true"')
  end

  it "parses empty string comparisons" do
    condition = parser.parse('env.MISSING == ""')

    expect(condition.expected_value).to eq("")
  end

  it "parses escaped quote characters" do
    condition = parser.parse('env.MESSAGE == "say \"hi\""')

    expect(condition.expected_value).to eq('say "hi"')
  end

  it "rejects malformed expressions" do
    expect { parser.parse("env.DEPLOY") }.to raise_error(ArgumentError, /unsupported if expression/)
  end

  it "rejects arbitrary Ruby code" do
    expect { parser.parse('system("rm -rf /")') }.to raise_error(ArgumentError, /unsupported if expression/)
  end

  it "rejects shell syntax" do
    expect { parser.parse('$(echo true)') }.to raise_error(ArgumentError, /unsupported if expression/)
  end

  it "rejects logical expressions" do
    expect { parser.parse('env.A == "x" && env.B == "y"') }.to raise_error(ArgumentError, /unsupported if expression/)
  end
end
