# frozen_string_literal: true

require "pathname"

module MiniCi
  class ArtifactPathResolver
    MatchResult = Struct.new(:sources, :warnings, :errors, keyword_init: true)

    def initialize(workspace:)
      @workspace = Pathname.new(workspace).realpath
    end

    INTERPOLATION = /\$\{\{\s*(.*?)\s*\}\}/

    def resolve(paths, env: {})
      sources = []
      warnings = []
      errors = []

      paths.each do |path|
        begin
          path = resolve_path_template(path, env)
        rescue StandardError => e
          errors << e.message
          next
        end
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

    def resolve_path_template(path, env)
      path.gsub(INTERPOLATION) do
        expression = Regexp.last_match(1).strip
        match = expression.match(/\Aenv\.([A-Za-z_][A-Za-z0-9_]*)\z/)
        raise "artifact path has unsupported expression #{expression.inspect}" unless match

        value = env.fetch(match[1], "")
        if value.include?("\0") || value.split(%r{[\\/]+}).include?("..") || Pathname.new(value).absolute?
          raise "artifact path environment value #{match[1].inspect} must stay inside the workspace"
        end

        value
      end
    end

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
      raise "artifact source #{path.inspect} resolves outside the workspace" unless inside_workspace?(real_path)

      validate_directory_tree(path) if File.directory?(path)

      real_path.to_s
    end

    def validate_directory_tree(path)
      Dir.glob(File.join(path, "**", "*"), File::FNM_DOTMATCH).each do |entry|
        next if [".", ".."].include?(File.basename(entry))

        real_path = Pathname.new(entry).realpath
        raise "artifact source #{entry.inspect} resolves outside the workspace" unless inside_workspace?(real_path)
      end
    end

    def inside_workspace?(path)
      path.to_s == @workspace.to_s || path.to_s.start_with?("#{@workspace}/")
    end
  end
end
