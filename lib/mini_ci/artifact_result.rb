# frozen_string_literal: true

module MiniCi
  class ArtifactResult
    attr_reader :requested_paths,
                :matched_sources,
                :copied_files,
                :copied_directories,
                :destination,
                :warnings,
                :errors

    def initialize(requested_paths:, matched_sources: [], copied_files: [], copied_directories: [], destination: nil, warnings: [], errors: [])
      @requested_paths = requested_paths.dup.freeze
      @matched_sources = matched_sources.dup.freeze
      @copied_files = copied_files.dup.freeze
      @copied_directories = copied_directories.dup.freeze
      @destination = destination
      @warnings = warnings.dup.freeze
      @errors = errors.dup.freeze
      freeze
    end

    def success?
      errors.empty?
    end

    def failed?
      !success?
    end

    def empty?
      copied_files.empty? && copied_directories.empty?
    end

    def copied_file_count
      copied_files.length
    end

    def warning_count
      warnings.length
    end

    def error_count
      errors.length
    end
  end
end
