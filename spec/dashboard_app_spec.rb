# frozen_string_literal: true

require "json"
require "rack/test"
require "mini_ci/dashboard/app"

RSpec.describe MiniCi::Dashboard::App do
  include Rack::Test::Methods

  class DashboardFakeLauncher
    def initialize(repository)
      @repository = repository
    end

    def submit(pipeline_file:, concurrency: nil, no_cache: false, plugin_files: [], plugin_dirs: [])
      @repository.create(pipeline_file: pipeline_file, source: "dashboard")
    end

    def cancel(run_id)
      @repository.cancel(run_id)
    end
  end

  def app
    described_class
  end

  let(:directory) { Dir.mktmpdir }
  let(:repository) do
    counter = 0
    MiniCi::RunRepository.new(
      root: File.join(directory, ".mini-ci", "runs"),
      workspace: directory,
      clock: -> { Time.utc(2026, 1, 2, 3, 4, 5) },
      token_generator: lambda {
        counter += 1
        format("%06x", counter)
      }
    )
  end

  before do
    header "Host", "127.0.0.1"
    described_class.set :repository, repository
    described_class.set :presenter, MiniCi::Dashboard::Presenter.new(repository: repository)
    described_class.set :launcher, DashboardFakeLauncher.new(repository)
  end

  after do
    FileUtils.remove_entry(directory) if directory && File.directory?(directory)
  end

  it "renders the dashboard home page and run list" do
    record = create_finished_run(status: "passed", pipeline_name: "Ruby Build")

    get "/"
    expect(last_response).to be_ok
    expect(last_response.body).to include("Overview")
    expect(last_response.body).to include("Local dashboard")
    expect(last_response.body).to include("Mini CI 1.0.0")
    expect(last_response.body).to include("Run history")
    expect(last_response.body).to include(record.fetch("run_id"))

    get "/runs?status=passed"
    expect(last_response).to be_ok
    expect(last_response.body).to include("Ruby Build")
    expect(last_response.body).to include("status-passed")
  end

  it "renders accurate navigation and responsive dashboard classes" do
    create_finished_run(status: "passed", pipeline_name: "Ruby Build")

    get "/runs"

    expect(last_response).to be_ok
    expect(last_response.body).to include("primary-nav")
    expect(last_response.body).to include('href="/runs" aria-current="page"')
    expect(last_response.body).to include("table-wrap")
    expect(last_response.body).to include("local-indicator")
  end

  it "renders run details and job details" do
    record = create_finished_run(status: "passed", pipeline_name: "Ruby Build")

    get "/runs/#{record.fetch("run_id")}"
    expect(last_response).to be_ok
    expect(last_response.body).to include("Ruby Build")
    expect(last_response.body).to include("Build")
    expect(last_response.body).to include("Execution details")
    expect(last_response.body).to include("data-confirm=")

    get "/runs/#{record.fetch("run_id")}/jobs/1"
    expect(last_response).to be_ok
    expect(last_response.body).to include("Unit tests")
    expect(last_response.body).to include("timeline")
    expect(last_response.body).to include("command-snippet")
  end

  it "renders failure summaries near the run header" do
    record = create_finished_run(status: "failed", pipeline_name: "Ruby Build")

    get "/runs/#{record.fetch("run_id")}"

    expect(last_response).to be_ok
    expect(last_response.body).to include("Failure summary")
    expect(last_response.body).to include("status-failed")
  end

  it "serves JSON APIs for runs, events, and output" do
    record = create_finished_run(status: "failed", pipeline_name: "Ruby Build")
    repository.output_writer(record.fetch("run_id")).puts("failure output")

    get "/api/runs"
    expect(JSON.parse(last_response.body).fetch("runs").first.fetch("status")).to eq("failed")

    get "/api/runs/#{record.fetch("run_id")}/events"
    expect(JSON.parse(last_response.body).fetch("events").map { |event| event["type"] }).to include("run_finished")

    get "/api/runs/#{record.fetch("run_id")}/output"
    expect(JSON.parse(last_response.body).fetch("text")).to include("failure output")
  end

  it "renders output logs" do
    record = create_finished_run(status: "passed", pipeline_name: "Ruby Build")
    repository.output_writer(record.fetch("run_id")).puts("hello from logs")

    get "/runs/#{record.fetch("run_id")}/output"
    expect(last_response).to be_ok
    expect(last_response.body).to include("hello from logs")
    expect(last_response.body).to include("data-log-viewer")
    expect(last_response.body).to include("data-copy-log")
  end

  it "renders non-ASCII output logs even without a UTF-8 locale" do
    record = create_finished_run(status: "passed", pipeline_name: "Ruby Build")
    repository.output_writer(record.fetch("run_id")).puts("Déploiement ✓ terminé")

    with_default_external_encoding("US-ASCII") do
      expect { get "/runs/#{record.fetch("run_id")}/output" }.not_to raise_error
    end

    expect(last_response).to be_ok
    expect(last_response.body).to include("Déploiement ✓ terminé")
  end

  it "escapes log output and pipeline names" do
    record = create_finished_run(status: "passed", pipeline_name: "<script>alert(1)</script>")
    repository.output_writer(record.fetch("run_id")).puts("<img src=x onerror=alert(1)>")

    get "/runs/#{record.fetch("run_id")}"
    expect(last_response.body).to include("&lt;script&gt;alert(1)&lt;/script&gt;")
    expect(last_response.body).not_to include("<script>alert(1)</script>")

    get "/runs/#{record.fetch("run_id")}/output"
    expect(last_response.body).to include("&lt;img src=x onerror=alert(1)&gt;")
    expect(last_response.body).not_to include("<img src=x onerror=alert(1)>")
  end

  it "serves artifacts while blocking traversal" do
    artifacts = File.join(directory, "artifacts")
    FileUtils.mkdir_p(artifacts)
    File.write(File.join(artifacts, "report.txt"), "artifact body")
    record = create_finished_run(status: "passed", pipeline_name: "Ruby Build", artifacts: artifacts)

    get "/runs/#{record.fetch("run_id")}/artifacts"
    expect(last_response).to be_ok
    expect(last_response.body).to include("report.txt")
    expect(last_response.body).to include("Relative path")
    expect(last_response.body).to include("bytes")

    get "/runs/#{record.fetch("run_id")}/artifacts/report.txt"
    expect(last_response).to be_ok
    expect(last_response.body).to include("artifact body")

    get "/runs/#{record.fetch("run_id")}/artifacts/../secret.txt"
    expect(last_response.status).to eq(404)
  end

  it "serves non-ASCII artifact content as text even without a UTF-8 locale" do
    artifacts = File.join(directory, "artifacts")
    FileUtils.mkdir_p(artifacts)
    File.write(File.join(artifacts, "report.txt"), "Déploiement ✓ terminé")
    record = create_finished_run(status: "passed", pipeline_name: "Ruby Build", artifacts: artifacts)

    with_default_external_encoding("US-ASCII") do
      expect { get "/runs/#{record.fetch("run_id")}/artifacts/report.txt" }.not_to raise_error
    end

    expect(last_response).to be_ok
    expect(last_response.content_type).to include("text/plain")
    expect(last_response.body).to include("Déploiement ✓ terminé")
  end

  it "requires CSRF tokens for state-changing requests" do
    post "/runs", pipeline_file: "pipeline.yml"

    expect(last_response.status).to eq(403)
  end

  it "creates a queued run from the launch form" do
    File.write(File.join(directory, "pipeline.yml"), "name: Demo\nsteps:\n  - name: One\n    run: echo ok\n")

    get "/run/new"
    expect(last_response.body).to include("Commands run locally with your current user permissions.")
    expect(last_response.body).to include("data-launch-form")
    token = last_response.body.match(/name="csrf_token" value="([^"]+)"/)[1]
    post "/runs", pipeline_file: File.join(directory, "pipeline.yml"), csrf_token: token

    expect(last_response.status).to eq(302)
    expect(repository.all_records.first.fetch("source")).to eq("dashboard")
  end

  private

  def create_finished_run(status:, pipeline_name:, artifacts: nil)
    record = repository.create(pipeline_file: "pipeline.yml")
    run_id = record.fetch("run_id")
    repository.mark_running(run_id, pipeline_name: pipeline_name)
    repository.finish(
      run_id,
      {
        "overall_status" => status,
        "pipeline_status" => status,
        "duration" => 1.23,
        "matrix" => false,
        "jobs" => [
          {
            "index" => 1,
            "name" => "Build",
            "status" => status,
            "items" => [
              {
                "index" => 1,
                "phase" => "step",
                "name" => "Unit tests",
                "command" => "bundle exec rspec",
                "status" => status,
                "duration" => 1.0,
                "attempts" => [{ "exit_status" => status == "passed" ? 0 : 1 }]
              }
            ]
          }
        ],
        "failures" => status == "failed" ? [{ "message" => "Unit tests failed with exit code 1" }] : [],
        "artifacts" => artifacts ? { "directory" => artifacts, "files" => 1 } : {},
        "cache" => {},
        "plugins" => [],
        "plugin_failures" => []
      }
    )
    repository.load(run_id)
  end
end
