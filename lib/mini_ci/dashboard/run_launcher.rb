# frozen_string_literal: true

require "stringio"
require "thread"

module MiniCi
  module Dashboard
    class RunLauncher
      MAX_WORKERS = 4

      def initialize(repository:, max_runs: 200, workers: MAX_WORKERS)
        @repository = repository
        @max_runs = max_runs
        @queue = Queue.new
        @running = {}
        @mutex = Mutex.new
        @workers = workers.times.map { Thread.new { worker_loop } }
        @workers.each { |worker| worker.report_on_exception = false }
      end

      def submit(pipeline_file:, concurrency: nil, no_cache: false, plugin_files: [], plugin_dirs: [])
        validate_pipeline_file!(pipeline_file)
        record = @repository.create(pipeline_file: pipeline_file, source: "dashboard")
        @queue << {
          run_id: record.fetch("run_id"),
          pipeline_file: pipeline_file,
          concurrency: concurrency,
          no_cache: no_cache,
          plugin_files: plugin_files,
          plugin_dirs: plugin_dirs
        }
        record
      end

      def cancel(run_id)
        @mutex.synchronize { @running[run_id] = :cancelled }
        @repository.cancel(run_id)
      end

      private

      def worker_loop
        loop do
          job = @queue.pop
          run_job(job)
        end
      end

      def run_job(job)
        return if cancelled?(job[:run_id])

        @mutex.synchronize { @running[job[:run_id]] = :running }
        @repository.mark_running(job[:run_id], pipeline_name: File.basename(job[:pipeline_file]), configured_concurrency: job[:concurrency] || "automatic")
        output = @repository.output_writer(job[:run_id])
        args = ["run", job[:pipeline_file], "--no-history"]
        args.concat(["--concurrency", job[:concurrency]]) if job[:concurrency] && !job[:concurrency].empty?
        args << "--no-cache" if job[:no_cache]
        job[:plugin_dirs].each { |path| args.concat(["--plugin-dir", path]) }
        job[:plugin_files].each { |path| args.concat(["--plugin", path]) }

        exit_code = MiniCi::CLI.new(arguments: args, output: output, error_output: output).call
        status = cancelled?(job[:run_id]) ? "cancelled" : (exit_code.zero? ? "passed" : "failed")
        @repository.finish(
          job[:run_id],
          {
            "overall_status" => status,
            "pipeline_status" => status,
            "duration" => nil,
            "attempts" => nil,
            "jobs" => [],
            "artifacts" => {},
            "cache" => {},
            "plugins" => [],
            "plugin_failures" => []
          }
        )
        @repository.prune(max_runs: @max_runs)
      rescue StandardError => e
        @repository.fail(job[:run_id], status: "internal_error", message: e.message)
      ensure
        @mutex.synchronize { @running.delete(job[:run_id]) }
      end

      def cancelled?(run_id)
        @mutex.synchronize { @running[run_id] == :cancelled }
      end

      def validate_pipeline_file!(path)
        raise UsageError, "Pipeline file is required" if path.to_s.strip.empty?
        raise FileNotFoundError, "#{path} was not found" unless File.file?(path)
        raise UsageError, "Pipeline file must be a YAML file" unless [".yml", ".yaml"].include?(File.extname(path))
      end
    end
  end
end

