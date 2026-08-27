# frozen_string_literal: true

MiniCi::Plugin.register(
  name: "policy-validator",
  version: "1.0.0",
  description: "Requires explicit pipeline and step names"
) do |plugin|
  plugin.validate_configuration do |configuration|
    messages = []
    messages << "pipeline name is required by company policy" unless configuration.name_explicit
    configuration.steps.each_with_index do |step, index|
      messages << "step #{index + 1} must have a non-empty name" if step.name.to_s.strip.empty?
    end
    messages
  end
end
