# frozen_string_literal: true

RSpec.describe MiniCi::ArtifactRunStore do
  it "creates deterministic run, job, and item directories with injected values" do
    workspace = Dir.mktmpdir
    time = Time.utc(2026, 7, 28, 10, 15, 30)

    store = described_class.new(
      root: "artifacts",
      workspace: workspace,
      clock: -> { time },
      token_generator: -> { "a1b2c3" }
    )
    job_dir = store.job_directory(index: 1, label: "ruby=3.2, database=sqlite")
    item_dir = store.item_directory(job_directory: job_dir, phase: :step, index: 2, name: "Run Tests!")

    expect(store.run_id).to eq("run-20260728T101530Z-a1b2c3")
    expect(job_dir).to end_with("job-001-ruby-3-2-database-sqlite")
    expect(item_dir).to end_with("step-002-run-tests")
    expect(File.directory?(item_dir)).to be(true)
  ensure
    FileUtils.remove_entry(workspace) if workspace
  end
end
