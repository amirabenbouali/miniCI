# frozen_string_literal: true

require "time"

module MiniCi
  module Dashboard
    class Presenter
      def initialize(repository:)
        @repository = repository
      end

      def summary(records)
        total = records.length
        passed = records.count { |record| record["status"] == "passed" }
        failed = records.count { |record| record["status"] == "failed" }
        running = records.count { |record| %w[queued running].include?(record["status"]) }
        rate = total.zero? ? "0%" : "#{((passed.to_f / total) * 100).round}%"
        {
          total: total,
          passed: passed,
          failed: failed,
          running: running,
          success_rate: rate
        }
      end

      def status_label(status)
        status.to_s.tr("_", " ").upcase
      end

      def format_duration(seconds)
        return "n/a" if seconds.nil?

        format("%.2fs", seconds)
      end

      def format_time(value)
        return "n/a" if value.nil? || value.to_s.empty?

        Time.parse(value).utc.iso8601
      rescue ArgumentError
        value
      end

      def artifact_count(record)
        record.dig("artifacts", "files").to_i
      end

      def cache_label(record)
        cache = record["cache"] || {}
        "#{cache["hits"].to_i} hits, #{cache["misses"].to_i} misses"
      end

      def failure_summary(record)
        failures = Array(record["failures"]) + Array(record["plugin_failures"])
        failures.first&.fetch("message", nil) || failures.first&.fetch("event", nil) || "None"
      end
    end
  end
end
