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
        durations = records.filter_map { |record| record["duration"] }.map(&:to_f)
        rate = total.zero? ? "0%" : "#{((passed.to_f / total) * 100).round}%"
        {
          total: total,
          passed: passed,
          failed: failed,
          running: running,
          success_rate: rate,
          average_duration: durations.empty? ? nil : durations.sum / durations.length
        }
      end

      def status_label(status)
        labels = {
          "internal_error" => "Failed",
          "passed" => "Passed",
          "failed" => "Failed",
          "running" => "Running",
          "queued" => "Pending",
          "pending" => "Pending",
          "cancelled" => "Cancelled",
          "skipped" => "Skipped",
          "timed_out" => "Timed out"
        }
        labels.fetch(status.to_s, status.to_s.tr("_", " ").capitalize)
      end

      def format_duration(seconds)
        return "n/a" if seconds.nil?

        format("%.2fs", seconds)
      end

      def relative_time(value, now: Time.now.utc)
        return "n/a" if value.nil? || value.to_s.empty?

        time = Time.parse(value).utc
        seconds = [(now - time).to_i, 0].max
        return "just now" if seconds < 10
        return "#{seconds}s ago" if seconds < 60

        minutes = seconds / 60
        return "#{minutes}m ago" if minutes < 60

        hours = minutes / 60
        return "#{hours}h ago" if hours < 24

        days = hours / 24
        "#{days}d ago"
      rescue ArgumentError
        value
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

      def job_count(record)
        Array(record["jobs"]).length
      end

      def plugin_count(record)
        Array(record["plugins"]).length
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
