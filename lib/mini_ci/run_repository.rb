# frozen_string_literal: true

require "fileutils"
require "json"
require "pathname"
require "securerandom"
require "time"

require_relative "run_event_writer"
require_relative "run_output_writer"

module MiniCi
  class RunRepository
    DEFAULT_ROOT = ".mini-ci/runs"
    RUN_ID_PATTERN = /\Arun-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{6}\z/
    TERMINAL_STATUSES = %w[passed failed cancelled internal_error].freeze

    attr_reader :root

    def initialize(root: DEFAULT_ROOT, workspace: Dir.pwd, clock: -> { Time.now.utc }, token_generator: lambda {
      SecureRandom.hex(3)
    })
      @workspace = Pathname.new(workspace).realpath
      @root = File.expand_path(root, @workspace.to_s)
      @clock = clock
      @token_generator = token_generator
      @mutex = Mutex.new
      FileUtils.mkdir_p(@root)
    end

    def create(pipeline_file:, source: "cli")
      run_id = "run-#{@clock.call.utc.strftime("%Y%m%dT%H%M%SZ")}-#{@token_generator.call}"
      directory = run_directory(run_id)
      FileUtils.mkdir_p(directory)
      record = {
        "run_id" => run_id,
        "status" => "queued",
        "pipeline_name" => nil,
        "pipeline_file" => pipeline_file,
        "source" => source,
        "created_at" => @clock.call.utc.iso8601,
        "started_at" => nil,
        "finished_at" => nil,
        "duration" => nil,
        "matrix" => false,
        "configured_concurrency" => nil,
        "actual_concurrency" => nil,
        "jobs" => [],
        "failures" => [],
        "plugins" => [],
        "plugin_failures" => [],
        "plugin_metadata" => {},
        "artifacts" => {},
        "cache" => {},
        "output_log" => "output.log",
        "events_log" => "events.jsonl"
      }
      write_record(run_id, record)
      output_writer(run_id)
      event_writer(run_id).append(:run_queued, run_id: run_id)
      record
    end

    def mark_running(run_id, pipeline_name:, configured_concurrency: nil, actual_concurrency: nil)
      update(run_id) do |record|
        record["status"] = "running"
        record["pipeline_name"] = pipeline_name
        record["started_at"] = @clock.call.utc.iso8601
        record["configured_concurrency"] = configured_concurrency
        record["actual_concurrency"] = actual_concurrency
      end
      event_writer(run_id).append(:run_started, run_id: run_id, pipeline: pipeline_name)
    end

    def finish(run_id, payload)
      update(run_id) do |record|
        record.merge!(payload)
        record["status"] = payload.fetch("overall_status")
        record["finished_at"] = @clock.call.utc.iso8601
      end
      event_writer(run_id).append(:run_finished, run_id: run_id, status: payload.fetch("overall_status"))
    end

    def fail(run_id, status:, message:)
      update(run_id) do |record|
        record["status"] = status
        record["finished_at"] = @clock.call.utc.iso8601
        record["failures"] = [{ "message" => message }]
      end
      event_writer(run_id).append(:run_failed, run_id: run_id, status: status, message: message)
    end

    def cancel(run_id)
      update(run_id) do |record|
        record["status"] = "cancelled" unless terminal?(record)
        record["finished_at"] ||= @clock.call.utc.iso8601
      end
      event_writer(run_id).append(:run_cancelled, run_id: run_id)
    end

    def list(status: nil, pipeline: nil, page: 1, per_page: 20)
      records = all_records
      records = records.select { |record| record["status"] == status } if status && !status.empty?
      if pipeline && !pipeline.empty?
        records = records.select { |record| record["pipeline_name"].to_s.downcase.include?(pipeline.downcase) }
      end
      offset = [[page.to_i, 1].max - 1, 0].max * per_page
      records.drop(offset).first(per_page)
    end

    def all_records
      Dir.glob(File.join(@root, "run-*", "run.json")).filter_map do |path|
        JSON.parse(File.read(path, encoding: Encoding::UTF_8))
      rescue JSON::ParserError, SystemCallError, EncodingError
        nil
      end.sort_by { |record| record["created_at"].to_s }.reverse
    end

    def corrupt_count
      Dir.glob(File.join(@root, "run-*", "run.json")).count do |path|
        JSON.parse(File.read(path, encoding: Encoding::UTF_8))
        false
      rescue JSON::ParserError, SystemCallError, EncodingError
        true
      end
    end

    def load(run_id)
      validate_run_id!(run_id)
      JSON.parse(File.read(record_path(run_id), encoding: Encoding::UTF_8))
    rescue JSON::ParserError, SystemCallError, EncodingError => e
      raise FileNotFoundError, "Run record could not be read: #{e.message}"
    end

    def delete(run_id)
      record = load(run_id)
      raise UsageError, "Only terminal runs can be deleted" unless terminal?(record)

      FileUtils.rm_rf(run_directory(run_id))
    end

    def prune(max_runs:)
      terminal = all_records.select { |record| terminal?(record) }
      terminal.drop(max_runs.to_i).each { |record| FileUtils.rm_rf(run_directory(record.fetch("run_id"))) }
    end

    def event_writer(run_id)
      validate_run_id!(run_id)
      RunEventWriter.new(File.join(run_directory(run_id), "events.jsonl"))
    end

    def output_writer(run_id)
      validate_run_id!(run_id)
      RunOutputWriter.new(output_path(run_id))
    end

    def output_path(run_id)
      validate_run_id!(run_id)
      File.join(run_directory(run_id), "output.log")
    end

    def events(run_id, after: 0)
      event_writer(run_id).read(after: after)
    end

    def safe_artifact_path(record, relative_path = "")
      root = record.dig("artifacts", "directory")
      raise FileNotFoundError, "Artifacts are no longer available" if root.nil? || root.empty?

      artifact_root = Pathname.new(root).realpath
      requested = relative_path.to_s
      if requested.include?("\0") || requested.split(%r{[\\/]+}).include?("..")
        raise UsageError,
              "Invalid artifact path"
      end

      path = Pathname.new(File.join(artifact_root.to_s, requested)).realpath
      unless path.to_s == artifact_root.to_s || path.to_s.start_with?("#{artifact_root}/")
        raise UsageError, "Invalid artifact path"
      end

      path.to_s
    end

    private

    def update(run_id)
      @mutex.synchronize do
        record = load(run_id)
        yield record
        write_record(run_id, record)
        record
      end
    end

    def write_record(run_id, record)
      path = record_path(run_id)
      tmp_path = "#{path}.tmp-#{$$}-#{Thread.current.object_id}"
      File.write(tmp_path, JSON.pretty_generate(record))
      File.rename(tmp_path, path)
    end

    def record_path(run_id)
      File.join(run_directory(run_id), "run.json")
    end

    def run_directory(run_id)
      validate_run_id!(run_id)
      File.join(@root, run_id)
    end

    def validate_run_id!(run_id)
      return if run_id.to_s.match?(RUN_ID_PATTERN)

      raise UsageError, "Invalid run id"
    end

    def terminal?(record)
      TERMINAL_STATUSES.include?(record["status"])
    end
  end
end
