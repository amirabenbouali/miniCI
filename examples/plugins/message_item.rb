# frozen_string_literal: true

MiniCi::Plugin.register(
  name: "message-plugin",
  version: "1.0.0",
  description: "Adds a message pipeline item"
) do |plugin|
  plugin.register_item_type(
    "message",
    validate: lambda do |input|
      text = input["text"]
      "message text must be a non-empty string" unless text.is_a?(String) && !text.strip.empty?
    end
  ) do |input, context|
    text = input.fetch("text")
    suffix = context.environment_variable("MATRIX_RUBY")
    message = suffix.empty? ? text : "#{text} (ruby #{suffix})"
    context.output.puts message

    MiniCi::Plugin::ItemResult.new(
      success: true,
      plugin_name: "message-plugin",
      item_type: "message",
      output: nil,
      metadata: {
        "message_length" => message.length
      }
    )
  end
end

