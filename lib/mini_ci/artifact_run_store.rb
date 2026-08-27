# frozen_string_literal: true

require "fileutils"
require "pathname"
require "securerandom"
require "time"

module MiniCi
  class ArtifactRunStore
    DEFAULT_ROOT = ".mini-ci/artifacts"

    attr_reader :root, :run_id, :run_directory, :started_at

    def initialize(root: DEFAULT_ROOT, workspace: Dir.pwd, clock: -> { Time.now.utc }, token_generator: lambda {
      SecureRandom.hex(3)
    })
      @workspace = File.expand_path(workspace)
      @root = expand_root(root)
      @started_at = clock.call.utc
      @run_id = "run-#{@started_at.strftime("%Y%m%dT%H%M%SZ")}-#{token_generator.call}"
      @run_directory = File.join(@root, @run_id)
      @mutex = Mutex.new
      validate_root!
      FileUtils.mkdir_p(@run_directory)
    end

    def job_directory(index:, label: nil)
      suffix = label.nil? || label.strip.empty? ? "" : "-#{sanitize(label)}"
      path = File.join(@run_directory, format("job-%03d%s", index, suffix))
      mkdir(path)
      path
    end

    def item_directory(job_directory:, phase:, index:, name:)
      path = File.join(job_directory, "#{phase_prefix(phase)}-#{format("%03d", index)}-#{sanitize(name)}")
      mkdir(path)
      path
    end

    def relative_to_run(path)
      Pathname.new(path).relative_path_from(Pathname.new(@run_directory)).to_s
    end

    private

    def expand_root(root)
      File.expand_path(root, @workspace)
    end

    def validate_root!
      raise ConfigurationError, "Invalid artifact destination: #{@root} is a file" if File.file?(@root)

      FileUtils.mkdir_p(@root)
    rescue SystemCallError => e
      raise ConfigurationError, "Invalid artifact destination: #{e.message}"
    end

    def mkdir(path)
      @mutex.synchronize { FileUtils.mkdir_p(path) }
      path
    end

    def sanitize(value)
      value.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-+\z/, "")[0, 80].then { |text| text.empty? ? "item" : text }
    end

    def phase_prefix(phase)
      case phase
      when :before_all
        "before-all"
      when :after_all
        "after-all"
      else
        "step"
      end
    end
  end
end
