# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "pathname"
require "securerandom"
require "time"

require_relative "artifact_path_resolver"
require_relative "cache_result"

module MiniCi
  class CacheStore
    DEFAULT_ROOT = ".mini-ci/cache"
    METADATA_FILE = "metadata.json"

    CacheEntry = Struct.new(
      :key,
      :storage_id,
      :created_at,
      :last_restored_at,
      :paths,
      :file_count,
      :size_bytes,
      :entry_directory,
      :data_directory,
      keyword_init: true
    )

    def initialize(root: DEFAULT_ROOT, workspace: Dir.pwd, clock: -> { Time.now.utc })
      @root = File.expand_path(root)
      @workspace = Pathname.new(workspace).realpath
      @resolver = ArtifactPathResolver.new(workspace: @workspace.to_s)
      @clock = clock
      @locks = Hash.new { |locks, key| locks[key] = Mutex.new }
      validate_root!
      FileUtils.mkdir_p(entries_root)
      FileUtils.mkdir_p(tmp_root)
    end

    attr_reader :root

    def restore(resolved_key:, restore_keys:)
      started_at = monotonic_time
      entry = exact_entry_for(resolved_key)
      status = :exact_hit

      unless entry
        entry = fallback_entry_for(restore_keys)
        status = :fallback_hit if entry
      end

      unless entry
        return CacheResult.new(
          configured: true,
          resolved_key: resolved_key,
          restore_status: :miss,
          restore_duration: monotonic_time - started_at
        )
      end

      warnings = []
      copied_files, copied_bytes = copy_cache_to_workspace(entry, warnings)
      touch_restore(entry)

      CacheResult.new(
        configured: true,
        resolved_key: resolved_key,
        restore_status: status,
        restore_source_key: entry.key,
        restore_duration: monotonic_time - started_at,
        restored_file_count: copied_files,
        restored_size_bytes: copied_bytes,
        warnings: warnings
      )
    rescue StandardError => e
      CacheResult.new(
        configured: true,
        resolved_key: resolved_key,
        restore_status: :miss,
        restore_duration: monotonic_time - started_at,
        warnings: ["cache restore failed: #{e.message}"]
      )
    end

    def save(resolved_key:, paths:)
      started_at = monotonic_time
      storage_id = storage_id_for(resolved_key)
      warnings = []
      resolved = @resolver.resolve(paths)
      warnings.concat(resolved.warnings)
      warnings.concat(resolved.errors)

      if resolved.sources.empty?
        return {
          saved_file_count: 0,
          saved_size_bytes: 0,
          save_duration: monotonic_time - started_at,
          warnings: warnings + ["cache save skipped: no configured paths matched files"]
        }
      end

      tmp_directory = File.join(tmp_root, "#{storage_id}-#{SecureRandom.hex(8)}")
      data_directory = File.join(tmp_directory, "data")
      saved_paths = []
      copied_files = 0
      copied_bytes = 0

      FileUtils.mkdir_p(data_directory)
      resolved.sources.each do |source|
        files, bytes, paths_for_source = copy_workspace_source_to_cache(source, data_directory)
        copied_files += files
        copied_bytes += bytes
        saved_paths.concat(paths_for_source)
      rescue StandardError => e
        warnings << "cache path #{source.inspect} could not be saved: #{e.message}"
      end

      if copied_files.zero?
        FileUtils.rm_rf(tmp_directory)
        return {
          saved_file_count: 0,
          saved_size_bytes: 0,
          save_duration: monotonic_time - started_at,
          warnings: warnings + ["cache save skipped: no files were copied"]
        }
      end

      metadata = metadata_for(
        key: resolved_key,
        storage_id: storage_id,
        paths: saved_paths.uniq.sort,
        file_count: copied_files,
        size_bytes: copied_bytes
      )
      File.write(File.join(tmp_directory, METADATA_FILE), JSON.pretty_generate(metadata))

      @locks[storage_id].synchronize do
        final_directory = entry_directory_for(storage_id)
        FileUtils.mkdir_p(File.dirname(final_directory))
        FileUtils.rm_rf(final_directory)
        FileUtils.mv(tmp_directory, final_directory)
      end

      {
        saved_file_count: copied_files,
        saved_size_bytes: copied_bytes,
        save_duration: monotonic_time - started_at,
        warnings: warnings
      }
    rescue StandardError => e
      FileUtils.rm_rf(tmp_directory) if defined?(tmp_directory) && tmp_directory
      {
        saved_file_count: 0,
        saved_size_bytes: 0,
        save_duration: monotonic_time - started_at,
        warnings: ["cache save failed: #{e.message}"]
      }
    end

    def list_entries
      Dir.glob(File.join(entries_root, "*", "*", METADATA_FILE)).filter_map do |metadata_path|
        entry_from_metadata(metadata_path)
      rescue StandardError
        nil
      end.sort_by { |entry| entry.created_at || Time.at(0).utc }.reverse
    end

    def clear!
      validate_root!
      count = list_entries.length
      FileUtils.rm_rf(entries_root)
      FileUtils.rm_rf(tmp_root)
      FileUtils.mkdir_p(entries_root)
      FileUtils.mkdir_p(tmp_root)
      count
    end

    private

    def validate_root!
      root_path = Pathname.new(@root)
      if root_path.to_s == "/" || root_path.to_s.strip.empty?
        raise UsageError, "cache directory is unsafe"
      end
    end

    def exact_entry_for(key)
      entry = read_entry(storage_id_for(key))
      entry if entry&.key == key
    end

    def fallback_entry_for(prefixes)
      prefixes.each do |prefix|
        entry = list_entries.select { |candidate| candidate.key.start_with?(prefix) }.max_by(&:created_at)
        return entry if entry
      end
      nil
    end

    def copy_cache_to_workspace(entry, warnings)
      copied_files = 0
      copied_bytes = 0
      Dir.glob(File.join(entry.data_directory, "**", "*"), File::FNM_DOTMATCH).sort.each do |source|
        next if [".", ".."].include?(File.basename(source))

        relative_path = Pathname.new(source).relative_path_from(Pathname.new(entry.data_directory)).to_s
        target = safe_workspace_target(relative_path)
        if File.directory?(source)
          FileUtils.mkdir_p(target)
        else
          FileUtils.mkdir_p(File.dirname(target))
          FileUtils.cp(source, target)
          copied_files += 1
          copied_bytes += File.size(source)
        end
      rescue StandardError => e
        warnings << "cache restore skipped #{relative_path.inspect}: #{e.message}"
      end
      [copied_files, copied_bytes]
    end

    def touch_restore(entry)
      metadata_path = File.join(entry.entry_directory, METADATA_FILE)
      metadata = JSON.parse(File.read(metadata_path, encoding: Encoding::UTF_8))
      metadata["last_restored_at"] = @clock.call.iso8601(6)
      File.write(metadata_path, JSON.pretty_generate(metadata))
    rescue StandardError
      nil
    end

    def copy_workspace_source_to_cache(source, data_directory)
      relative_path = @resolver.relative_path_for(source)
      target = File.join(data_directory, relative_path)
      copied_files = 0
      copied_bytes = 0
      saved_paths = []

      if File.directory?(source)
        FileUtils.mkdir_p(target)
        Dir.glob(File.join(source, "**", "*"), File::FNM_DOTMATCH).sort.each do |entry|
          next if [".", ".."].include?(File.basename(entry))

          entry_relative_path = @resolver.relative_path_for(entry)
          entry_target = File.join(data_directory, entry_relative_path)
          if File.directory?(entry)
            FileUtils.mkdir_p(entry_target)
          else
            FileUtils.mkdir_p(File.dirname(entry_target))
            FileUtils.cp(entry, entry_target)
            copied_files += 1
            copied_bytes += File.size(entry)
            saved_paths << entry_relative_path
          end
        end
      else
        FileUtils.mkdir_p(File.dirname(target))
        FileUtils.cp(source, target)
        copied_files += 1
        copied_bytes += File.size(source)
        saved_paths << relative_path
      end

      [copied_files, copied_bytes, saved_paths]
    end

    def safe_workspace_target(relative_path)
      if Pathname.new(relative_path).absolute? || relative_path.split(/[\\\/]+/).include?("..")
        raise "cache entry path must stay inside the workspace"
      end

      target = File.expand_path(File.join(@workspace.to_s, relative_path))
      unless target == @workspace.to_s || target.start_with?("#{@workspace}/")
        raise "cache entry path resolves outside the workspace"
      end

      target
    end

    def metadata_for(key:, storage_id:, paths:, file_count:, size_bytes:)
      now = @clock.call.iso8601(6)
      {
        "version" => 1,
        "key" => key,
        "storage_id" => storage_id,
        "created_at" => now,
        "last_restored_at" => nil,
        "paths" => paths,
        "file_count" => file_count,
        "size_bytes" => size_bytes
      }
    end

    def read_entry(storage_id)
      metadata_path = File.join(entry_directory_for(storage_id), METADATA_FILE)
      return nil unless File.file?(metadata_path)

      entry_from_metadata(metadata_path)
    end

    def entry_from_metadata(metadata_path)
      metadata = JSON.parse(File.read(metadata_path, encoding: Encoding::UTF_8))
      entry_directory = File.dirname(metadata_path)
      CacheEntry.new(
        key: metadata.fetch("key"),
        storage_id: metadata.fetch("storage_id"),
        created_at: parse_time(metadata["created_at"]),
        last_restored_at: parse_time(metadata["last_restored_at"]),
        paths: Array(metadata["paths"]),
        file_count: metadata["file_count"].to_i,
        size_bytes: metadata["size_bytes"].to_i,
        entry_directory: entry_directory,
        data_directory: File.join(entry_directory, "data")
      )
    end

    def parse_time(value)
      value ? Time.iso8601(value) : nil
    end

    def storage_id_for(key)
      Digest::SHA256.hexdigest(key)
    end

    def entry_directory_for(storage_id)
      File.join(entries_root, storage_id[0, 2], storage_id)
    end

    def entries_root
      File.join(@root, "entries")
    end

    def tmp_root
      File.join(@root, "tmp")
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
