# frozen_string_literal: true

require "fileutils"
require "set"

require_relative "artifact_path_resolver"
require_relative "artifact_result"

module MiniCi
  class ArtifactCollector
    def initialize(workspace:)
      @workspace = workspace
      @resolver = ArtifactPathResolver.new(workspace: workspace)
    end

    def collect(definition, destination:, env: {})
      resolved = @resolver.resolve(definition.paths, env: env)
      copied_files = []
      copied_directories = []
      copied_sources = Set.new
      errors = resolved.errors.dup

      FileUtils.mkdir_p(destination)
      resolved.sources.each do |source|
        copy_source(source, destination, copied_files, copied_directories, copied_sources)
      rescue StandardError => e
        errors << e.message
      end

      ArtifactResult.new(
        requested_paths: definition.paths,
        matched_sources: resolved.sources,
        copied_files: copied_files,
        copied_directories: copied_directories,
        destination: destination,
        warnings: resolved.warnings,
        errors: errors
      )
    end

    private

    def copy_source(source, destination, copied_files, copied_directories, copied_sources)
      relative_path = @resolver.relative_path_for(source)
      target = File.join(destination, relative_path)

      if File.directory?(source)
        copied_directories << relative_path
        copy_directory(source, target, destination, copied_files, copied_directories, copied_sources)
      else
        return if copied_sources.include?(source)

        FileUtils.mkdir_p(File.dirname(target))
        FileUtils.cp(source, target)
        copied_sources << source
        copied_files << relative_path
      end
    end

    def copy_directory(source, target, root_destination, copied_files, copied_directories, copied_sources)
      FileUtils.mkdir_p(target)
      Dir.glob(File.join(source, "**", "*"), File::FNM_DOTMATCH).sort.each do |entry|
        next if [".", ".."].include?(File.basename(entry))

        relative_path = @resolver.relative_path_for(entry)
        target_entry = File.join(root_destination, relative_path)
        if File.directory?(entry)
          FileUtils.mkdir_p(target_entry)
          copied_directories << relative_path
        else
          real_entry = File.realpath(entry)
          next if copied_sources.include?(real_entry)

          FileUtils.mkdir_p(File.dirname(target_entry))
          FileUtils.cp(entry, target_entry)
          copied_sources << real_entry
          copied_files << relative_path
        end
      end
    end
  end
end
