# frozen_string_literal: true

require "pathname"

module MiniCi
  module Plugin
    class Loader
      DEFAULT_DIRECTORY = ".mini-ci/plugins"

      def initialize(registry:, workspace: Dir.pwd)
        @registry = registry
        @workspace = Pathname.new(workspace).realpath
      end

      def load(default: true, directories: [], files: [])
        paths = []
        paths.concat(discover_default) if default
        directories.each { |directory| paths.concat(discover_directory(directory, explicit: true)) }
        files.each { |file| paths << validate_file(file) }
        paths.each { |path| load_file(path) }
        @registry.plugins
      end

      def discover_default
        directory = File.expand_path(DEFAULT_DIRECTORY, @workspace.to_s)
        return [] unless Dir.exist?(directory)

        discover_directory(directory, explicit: false)
      end

      def discover_directory(directory, explicit:)
        expanded = File.expand_path(directory)
        raise PluginLoadError, "Plugin directory #{directory} was not found" unless Dir.exist?(expanded)
        raise PluginLoadError, "#{directory} is a file, not a plugin directory" if File.file?(expanded)

        root = Pathname.new(expanded).realpath
        Dir.glob(File.join(expanded, "**", "*.rb")).sort.map do |path|
          canonical = Pathname.new(path).realpath
          if !explicit && !inside_directory?(canonical, root)
            raise PluginLoadError, "Plugin file #{path} resolves outside #{directory}"
          end

          validate_readable_ruby_file(path, canonical)
        end
      end

      def validate_file(file)
        expanded = File.expand_path(file)
        raise PluginLoadError, "Plugin file #{file} was not found" unless File.exist?(expanded)
        raise PluginLoadError, "#{file} is a directory, not a plugin file" if File.directory?(expanded)
        raise PluginLoadError, "Plugin file #{file} must be a Ruby .rb file" unless File.extname(expanded) == ".rb"

        validate_readable_ruby_file(file, Pathname.new(expanded).realpath)
      end

      def load_file(path)
        canonical = Pathname.new(path).realpath.to_s
        return if @registry.loaded?(canonical)

        before = @registry.plugins
        Kernel.load(canonical)
        (@registry.plugins - before).each { |plugin| plugin.source_path = canonical }
        @registry.mark_loaded(canonical)
      rescue SyntaxError, StandardError => e
        raise PluginLoadError, "Failed to load plugin #{path}: #{e.class}: #{e.message}"
      end

      private

      def validate_readable_ruby_file(display_path, canonical)
        raise PluginLoadError, "Plugin file #{display_path} is not readable" unless File.readable?(canonical.to_s)

        canonical.to_s
      end

      def inside_directory?(path, root)
        path.to_s == root.to_s || path.to_s.start_with?("#{root}/")
      end
    end
  end
end
