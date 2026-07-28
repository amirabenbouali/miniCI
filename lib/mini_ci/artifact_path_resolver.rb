# frozen_string_literal: true

require "pathname"

module MiniCi
  class ArtifactPathResolver
    MatchResult = Struct.new(:sources, :warnings, :errors, keyword_init: true)

    def initialize(workspace:)
      @workspace = Pathname.new(workspace).realpath
    end

    def resolve(paths)
      sources = []
      warnings = []
      errors = []

      paths.each do |path|
        matches = matches_for(path)
        warnings << "artifact path #{path.inspect} did not match any files" if matches.empty?

        matches.each do |match|
          safe_source = safe_source_for(match)
          sources << safe_source if safe_source
        rescue StandardError => e
          errors << e.message
        end
      end

      MatchResult.new(sources: sources.uniq, warnings: warnings, errors: errors)
    end

    def relative_path_for(source)
      Pathname.new(source).realpath.relative_path_from(@workspace).to_s
    end

    private

    def matches_for(path)
      full_pattern = File.join(@workspace.to_s, path)
      if glob_pattern?(path)
        Dir.glob(full_pattern, File::FNM_DOTMATCH).reject { |entry| [".", ".."].include?(File.basename(entry)) }
      elsif File.exist?(full_pattern) || File.symlink?(full_pattern)
        [full_pattern]
      else
        []
      end
    end

    def glob_pattern?(path)
      path.match?(/[*?\[]/)
    end

    def safe_source_for(path)
      real_path = Pathname.new(path).realpath
      unless inside_workspace?(real_path)
        raise "artifact source #{path.inspect} resolves outside the workspace"
      end

      if File.directory?(path)
        validate_directory_tree(path)
      end

      real_path.to_s
    end

    def validate_directory_tree(path)
      Dir.glob(File.join(path, "**", "*"), File::FNM_DOTMATCH).each do |entry|
        next if [".", ".."].include?(File.basename(entry))

        real_path = Pathname.new(entry).realpath
        unless inside_workspace?(real_path)
          raise "artifact source #{entry.inspect} resolves outside the workspace"
        end
      end
    end

    def inside_workspace?(path)
      path.to_s == @workspace.to_s || path.to_s.start_with?("#{@workspace}/")
    end
  end
end
