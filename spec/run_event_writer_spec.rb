# frozen_string_literal: true

RSpec.describe MiniCi::RunEventWriter do
  let(:directory) { Dir.mktmpdir }

  after do
    FileUtils.remove_entry(directory) if directory && File.directory?(directory)
  end

  it "appends JSONL events and reads from a cursor" do
    writer = described_class.new(File.join(directory, "events.jsonl"), clock: -> { Time.utc(2026, 1, 2, 3, 4, 5) })

    writer.append(:run_started, run_id: "run-1")
    writer.append(:step_finished, nested: { ok: true })

    result = writer.read(after: 1)
    expect(result.fetch("events").length).to eq(1)
    expect(result.fetch("events").first.fetch("type")).to eq("step_finished")
    expect(result.fetch("next_cursor")).to eq(2)
  end

  it "reads non-ASCII event payloads even without a UTF-8 locale" do
    writer = described_class.new(File.join(directory, "events.jsonl"), clock: -> { Time.utc(2026, 1, 2, 3, 4, 5) })
    writer.append(:job_completed, message: "Déploiement ✓ terminé")

    result = nil
    with_default_external_encoding("US-ASCII") do
      expect { result = writer.read }.not_to raise_error
    end

    expect(result.fetch("events").first.fetch("message")).to eq("Déploiement ✓ terminé")
  end
end
