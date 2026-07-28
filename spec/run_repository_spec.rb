# frozen_string_literal: true

require "json"

RSpec.describe MiniCi::RunRepository do
  def repository(root: File.join(directory, ".mini-ci", "runs"))
    counter = 0
    described_class.new(
      root: root,
      workspace: directory,
      clock: -> { Time.utc(2026, 1, 2, 3, 4, 5) },
      token_generator: -> { counter += 1; format("%06x", counter) }
    )
  end

  let(:directory) { Dir.mktmpdir }

  after do
    FileUtils.remove_entry(directory) if directory && File.directory?(directory)
  end

  it "creates a queued run record with event and output files" do
    record = repository.create(pipeline_file: "pipeline.yml")

    expect(record["status"]).to eq("queued")
    expect(File).to exist(File.join(repository.root, record.fetch("run_id"), "run.json"))
    expect(repository.events(record.fetch("run_id")).fetch("events").first.fetch("type")).to eq("run_queued")
    expect(File).to exist(repository.output_path(record.fetch("run_id")))
  end

  it "records running and final status with atomic JSON content" do
    repo = repository
    record = repo.create(pipeline_file: "pipeline.yml")
    run_id = record.fetch("run_id")

    repo.mark_running(run_id, pipeline_name: "Example", configured_concurrency: 2)
    repo.finish(run_id, "overall_status" => "passed", "pipeline_status" => "passed", "jobs" => [])

    saved = repo.load(run_id)
    expect(saved["status"]).to eq("passed")
    expect(saved["pipeline_name"]).to eq("Example")
    expect(saved["configured_concurrency"]).to eq(2)
    expect(saved["finished_at"]).not_to be_nil
  end

  it "filters by status and pipeline name" do
    repo = repository
    first = repo.create(pipeline_file: "one.yml")
    second = repo.create(pipeline_file: "two.yml")
    repo.mark_running(first.fetch("run_id"), pipeline_name: "Ruby Build")
    repo.finish(first.fetch("run_id"), "overall_status" => "passed", "pipeline_status" => "passed", "jobs" => [])
    repo.mark_running(second.fetch("run_id"), pipeline_name: "Docs Build")
    repo.finish(second.fetch("run_id"), "overall_status" => "failed", "pipeline_status" => "failed", "jobs" => [])

    expect(repo.list(status: "passed").map { |run| run["pipeline_name"] }).to eq(["Ruby Build"])
    expect(repo.list(pipeline: "docs").map { |run| run["pipeline_name"] }).to eq(["Docs Build"])
  end

  it "refuses unsafe run ids" do
    expect { repository.load("../run-20260102T030405Z-000001") }.to raise_error(MiniCi::UsageError, /Invalid run id/)
  end

  it "keeps artifact browsing inside the recorded artifact directory" do
    repo = repository
    artifacts = File.join(directory, "artifacts")
    FileUtils.mkdir_p(artifacts)
    File.write(File.join(artifacts, "report.txt"), "ok")
    record = repo.create(pipeline_file: "pipeline.yml")
    repo.finish(
      record.fetch("run_id"),
      "overall_status" => "passed",
      "pipeline_status" => "passed",
      "jobs" => [],
      "artifacts" => { "directory" => artifacts }
    )

    saved = repo.load(record.fetch("run_id"))
    expect(repo.safe_artifact_path(saved, "report.txt")).to eq(File.realpath(File.join(artifacts, "report.txt")))
    expect { repo.safe_artifact_path(saved, "../secret.txt") }.to raise_error(MiniCi::UsageError)
  end
end
