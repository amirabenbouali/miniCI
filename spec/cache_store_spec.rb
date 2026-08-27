# frozen_string_literal: true

require "tmpdir"

RSpec.describe MiniCi::CacheStore do
  def with_workspace
    directory = Dir.mktmpdir
    yield directory
  ensure
    FileUtils.remove_entry(directory) if directory
  end

  it "reports a miss when no matching cache exists" do
    with_workspace do |workspace|
      store = described_class.new(root: File.join(workspace, ".mini-ci/cache"), workspace: workspace)

      result = store.restore(resolved_key: "bundle-a", restore_keys: [])

      expect(result).to be_miss
      expect(result.restored_file_count).to eq(0)
    end
  end

  it "saves and restores files by exact key" do
    with_workspace do |workspace|
      cache_root = File.join(workspace, ".mini-ci/cache")
      FileUtils.mkdir_p(File.join(workspace, "vendor/bundle"))
      File.write(File.join(workspace, "vendor/bundle/gem.txt"), "cached")
      store = described_class.new(root: cache_root, workspace: workspace)

      save = store.save(resolved_key: "bundle-a", paths: ["vendor/bundle"])
      FileUtils.rm_rf(File.join(workspace, "vendor/bundle"))
      result = store.restore(resolved_key: "bundle-a", restore_keys: [])

      expect(save[:saved_file_count]).to eq(1)
      expect(result).to be_exact_hit
      expect(File.read(File.join(workspace, "vendor/bundle/gem.txt"))).to eq("cached")
    end
  end

  it "restores a non-ASCII cache key even without a UTF-8 locale" do
    with_workspace do |workspace|
      cache_root = File.join(workspace, ".mini-ci/cache")
      FileUtils.mkdir_p(File.join(workspace, "vendor/bundle"))
      File.write(File.join(workspace, "vendor/bundle/gem.txt"), "cached")
      store = described_class.new(root: cache_root, workspace: workspace)
      store.save(resolved_key: "bundle-Déploiement-✓", paths: ["vendor/bundle"])
      FileUtils.rm_rf(File.join(workspace, "vendor/bundle"))

      result = nil
      with_default_external_encoding("US-ASCII") do
        expect { result = store.restore(resolved_key: "bundle-Déploiement-✓", restore_keys: []) }.not_to raise_error
      end

      expect(result).to be_exact_hit
      expect(File.read(File.join(workspace, "vendor/bundle/gem.txt"))).to eq("cached")
    end
  end

  it "restores the newest matching fallback prefix" do
    with_workspace do |workspace|
      cache_root = File.join(workspace, ".mini-ci/cache")
      store = described_class.new(root: cache_root, workspace: workspace)

      FileUtils.mkdir_p(File.join(workspace, "tmp/deps"))
      File.write(File.join(workspace, "tmp/deps/value.txt"), "old")
      store.save(resolved_key: "bundle-old", paths: ["tmp/deps"])

      File.write(File.join(workspace, "tmp/deps/value.txt"), "new")
      store.save(resolved_key: "bundle-new", paths: ["tmp/deps"])

      FileUtils.rm_rf(File.join(workspace, "tmp/deps"))
      result = store.restore(resolved_key: "bundle-missing", restore_keys: ["bundle-"])

      expect(result).to be_fallback_hit
      expect(result.restore_source_key).to eq("bundle-new")
      expect(File.read(File.join(workspace, "tmp/deps/value.txt"))).to eq("new")
    end
  end

  it "warns instead of failing when save paths do not match" do
    with_workspace do |workspace|
      store = described_class.new(root: File.join(workspace, ".mini-ci/cache"), workspace: workspace)

      save = store.save(resolved_key: "missing", paths: ["tmp/missing"])

      expect(save[:saved_file_count]).to eq(0)
      expect(save[:warnings].join).to include("no configured paths matched")
    end
  end
end
