# frozen_string_literal: true

RSpec.describe MiniCi::ArtifactCollector do
  def write_file(path, content = "content")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  it "copies files and directories while preserving relative structure" do
    workspace = Dir.mktmpdir
    destination = File.join(workspace, "artifacts")
    write_file(File.join(workspace, "coverage/index.txt"), "coverage")
    write_file(File.join(workspace, "reports/results.xml"), "xml")
    definition = MiniCi::ArtifactDefinition.new(paths: ["coverage/", "reports/results.xml"])

    result = described_class.new(workspace: workspace).collect(definition, destination: destination)

    expect(result).to be_success
    expect(File.read(File.join(destination, "coverage/index.txt"))).to eq("coverage")
    expect(File.read(File.join(destination, "reports/results.xml"))).to eq("xml")
    expect(result.copied_file_count).to eq(2)
  ensure
    FileUtils.remove_entry(workspace) if workspace
  end

  it "records missing path warnings without failing" do
    workspace = Dir.mktmpdir
    destination = File.join(workspace, "artifacts")
    definition = MiniCi::ArtifactDefinition.new(paths: ["missing/"])

    result = described_class.new(workspace: workspace).collect(definition, destination: destination)

    expect(result).to be_success
    expect(result.warnings).not_to be_empty
  ensure
    FileUtils.remove_entry(workspace) if workspace
  end

  it "avoids duplicate copied files from overlapping paths" do
    workspace = Dir.mktmpdir
    destination = File.join(workspace, "artifacts")
    write_file(File.join(workspace, "logs/job.log"), "log")
    definition = MiniCi::ArtifactDefinition.new(paths: ["logs/", "logs/**/*.log"])

    result = described_class.new(workspace: workspace).collect(definition, destination: destination)

    expect(result).to be_success
    expect(result.copied_files.count("logs/job.log")).to eq(1)
  ensure
    FileUtils.remove_entry(workspace) if workspace
  end
end
