# frozen_string_literal: true

RSpec.describe MiniCi::Condition do
  def condition(operator: "==", expected_value: "true")
    described_class.new(
      variable_name: "DEPLOY",
      operator: operator,
      expected_value: expected_value,
      source: "env.DEPLOY #{operator} #{expected_value.inspect}"
    )
  end

  it "evaluates equality as true" do
    expect(condition.evaluate("DEPLOY" => "true")).to be(true)
  end

  it "evaluates equality as false" do
    expect(condition.evaluate("DEPLOY" => "false")).to be(false)
  end

  it "evaluates inequality as true" do
    expect(condition(operator: "!=", expected_value: "production").evaluate("DEPLOY" => "staging")).to be(true)
  end

  it "evaluates inequality as false" do
    expect(condition(operator: "!=", expected_value: "production").evaluate("DEPLOY" => "production")).to be(false)
  end

  it "treats missing variables as empty strings" do
    expect(condition(expected_value: "").evaluate({})).to be(true)
  end

  it "does not mutate the provided environment" do
    environment = { "DEPLOY" => "true" }

    condition.evaluate(environment)

    expect(environment).to eq("DEPLOY" => "true")
  end

  it "treats values as strings" do
    expect(condition(expected_value: "123").evaluate("DEPLOY" => 123)).to be(true)
  end
end
