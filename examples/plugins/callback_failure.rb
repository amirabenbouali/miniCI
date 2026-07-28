# frozen_string_literal: true

MiniCi::Plugin.register(
  name: "callback-failure",
  version: "1.0.0",
  description: "Raises during after_run for demonstration"
) do |plugin|
  plugin.after_run do |_context|
    raise "intentional callback failure"
  end
end

