# frozen_string_literal: true

require "json"
require "fileutils"

MiniCi::Plugin.register(
  name: "run-logger",
  version: "1.0.0",
  description: "Writes a small JSON log for each run"
) do |plugin|
  plugin.before_run do |context|
    context.metadata["run_logger"] = {
      "started" => true,
      "run_id" => context.run_id
    }
  end

  plugin.after_run(serial: true) do |context|
    FileUtils.mkdir_p("tmp/plugin-output")
    payload = {
      "run_id" => context.run_id,
      "status" => context.result.status,
      "workspace" => context.workspace
    }
    File.write("tmp/plugin-output/run-log.json", JSON.pretty_generate(payload))

    context.metadata["run_logger"] = {
      "status" => context.result.status,
      "log_path" => "tmp/plugin-output/run-log.json"
    }
  end
end
