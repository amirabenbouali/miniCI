# frozen_string_literal: true

RSpec.describe MiniCi::ArtifactPathResolver do
  def write_file(path, content = "content")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  it "resolves direct files, directories, and globs without duplicates" do
    directory = Dir.mktmpdir
    write_file(File.join(directory, "reports/results.xml"))
    write_file(File.join(directory, "logs/a.log"))
    resolver = described_class.new(workspace: directory)

    result = resolver.resolve(["reports/results.xml", "logs/", "logs/**/*.log"])

    expect(result.errors).to be_empty
    expect(result.warnings).to be_empty
    expect(result.sources.length).to eq(3)
    expect(result.sources.map { |path| resolver.relative_path_for(path) }).to include("reports/results.xml", "logs", "logs/a.log")
  ensure
    FileUtils.remove_entry(directory) if directory
  end

  it "records warnings for missing paths" do
    directory = Dir.mktmpdir
    resolver = described_class.new(workspace: directory)

    result = resolver.resolve(["missing/"])

    expect(result.sources).to be_empty
    expect(result.warnings.first).to include("missing/")
  ensure
    FileUtils.remove_entry(directory) if directory
  end

  it "rejects symlinks resolving outside the workspace" do
    directory = Dir.mktmpdir
    outside = Dir.mktmpdir
    write_file(File.join(outside, "secret.txt"))
    File.symlink(File.join(outside, "secret.txt"), File.join(directory, "secret-link"))
    resolver = described_class.new(workspace: directory)

    result = resolver.resolve(["secret-link"])

    expect(result.errors.first).to include("outside the workspace")
  ensure
    FileUtils.remove_entry(directory) if directory
    FileUtils.remove_entry(outside) if outside
  end
end
