# frozen_string_literal: true

require "tmpdir"

RSpec.describe MiniCi::CacheKeyResolver do
  def with_workspace
    directory = Dir.mktmpdir
    yield directory
  ensure
    FileUtils.remove_entry(directory) if directory
  end

  it "resolves SHA-256 checksum expressions" do
    with_workspace do |workspace|
      File.write(File.join(workspace, "lockfile"), "dependencies\n")
      digest = Digest::SHA256.file(File.join(workspace, "lockfile")).hexdigest

      key = described_class.new(workspace: workspace).resolve('bundle-${{ checksum("lockfile") }}', env: {})

      expect(key).to eq("bundle-#{digest}")
    end
  end

  it "resolves environment expressions" do
    with_workspace do |workspace|
      key = described_class.new(workspace: workspace).resolve("ruby-${{ env.MATRIX_RUBY }}",
                                                              env: { "MATRIX_RUBY" => "3.2" })

      expect(key).to eq("ruby-3.2")
    end
  end

  it "rejects unsupported expressions without evaluation" do
    with_workspace do |workspace|
      resolver = described_class.new(workspace: workspace)

      expect { resolver.resolve('${{ system("rm -rf .") }}', env: {}) }
        .to raise_error(MiniCi::ConfigurationError, /unsupported expression/)
    end
  end

  it "rejects checksum paths outside the workspace" do
    with_workspace do |workspace|
      resolver = described_class.new(workspace: workspace)

      expect { resolver.resolve('${{ checksum("../Gemfile.lock") }}', env: {}) }
        .to raise_error(MiniCi::ConfigurationError, /must stay inside the workspace/)
    end
  end

  it "rejects missing checksum files" do
    with_workspace do |workspace|
      resolver = described_class.new(workspace: workspace)

      expect { resolver.resolve('${{ checksum("missing.lock") }}', env: {}) }
        .to raise_error(MiniCi::ConfigurationError, /does not exist/)
    end
  end
end
