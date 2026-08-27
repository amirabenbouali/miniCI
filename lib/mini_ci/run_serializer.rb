# frozen_string_literal: true

require_relative "plugin"

module MiniCi
  class RunSerializer
    def serialize_result(result, matrix:, plugin_failures: [], plugin_metadata: nil, registry: Plugin.registry)
      base = {
        "overall_status" => (result.success? && plugin_failures.empty? ? "passed" : "failed"),
        "pipeline_status" => result.success? ? "passed" : "failed",
        "duration" => result.total_duration,
        "attempts" => result.total_attempts,
        "artifacts" => artifact_summary(result),
        "cache" => cache_summary(result),
        "plugins" => registry.plugins.map(&:metadata),
        "plugin_failures" => plugin_failures.map(&:to_h),
        "plugin_metadata" => plugin_metadata ? plugin_metadata.to_h : {}
      }

      if matrix
        base.merge(
          "matrix" => true,
          "configured_jobs" => result.job_count,
          "configured_concurrency" => result.requested_concurrency,
          "actual_concurrency" => result.actual_worker_count,
          "jobs" => result.matrix_job_results.each_with_index.map { |job, index| matrix_job(job, index + 1) }
        )
      else
        base.merge(
          "matrix" => false,
          "configured_jobs" => 1,
          "actual_concurrency" => 1,
          "jobs" => [pipeline_job(result, 1, result.name)]
        )
      end
    end

    private

    def matrix_job(job, index)
      pipeline_job(job.pipeline_result, index, job.display_name).merge(
        "matrix_values" => job.combination.environment
      )
    end

    def pipeline_job(result, index, name)
      {
        "index" => index,
        "name" => name,
        "status" => result.success? ? "passed" : "failed",
        "duration" => result.total_duration,
        "items" => result.all_results.each_with_index.map { |item, item_index| item_result(item, item_index + 1) }
      }
    end

    def item_result(item, index)
      {
        "index" => index,
        "phase" => item.category.to_s,
        "name" => item.step.name,
        "command" => item.step.command,
        "uses" => item.step.uses,
        "status" => if item.skipped?
                      "skipped"
                    else
                      (item.success? ? "passed" : "failed")
                    end,
        "duration" => item.duration,
        "skip_reason" => item.skip_reason&.to_s,
        "attempts" => item.attempts.map { |attempt| attempt_result(attempt) },
        "artifact" => artifact_result(item.artifact_result),
        "cache" => cache_result(item.cache_result),
        "plugin_failure" => item.plugin_failure&.to_h,
        "plugin_item" => plugin_item_result(item.plugin_item_result)
      }
    end

    def attempt_result(attempt)
      {
        "attempt_number" => attempt.attempt_number,
        "status" => attempt.success? ? "passed" : "failed",
        "exit_status" => attempt.exit_status,
        "duration" => attempt.duration,
        "timed_out" => attempt.timed_out?,
        "timeout" => attempt.timeout
      }
    end

    def artifact_result(artifact)
      return nil unless artifact

      {
        "files" => artifact.copied_file_count,
        "warnings" => artifact.warnings,
        "errors" => artifact.errors,
        "destination" => artifact.destination
      }
    end

    def cache_result(cache)
      return nil unless cache

      {
        "restore_status" => cache.restore_status.to_s,
        "resolved_key" => cache.resolved_key,
        "restore_source_key" => cache.restore_source_key,
        "restored_files" => cache.restored_file_count,
        "saved_files" => cache.saved_file_count,
        "restored_bytes" => cache.restored_size_bytes,
        "saved_bytes" => cache.saved_size_bytes,
        "warnings" => cache.warnings,
        "errors" => cache.errors
      }
    end

    def plugin_item_result(result)
      return nil unless result

      {
        "plugin" => result.plugin_name,
        "uses" => result.item_type,
        "status" => result.success? ? "passed" : "failed",
        "metadata" => result.metadata
      }
    end

    def artifact_summary(result)
      {
        "files" => result.artifact_count,
        "warnings" => result.artifact_warning_count,
        "failures" => result.artifact_failure_count,
        "directory" => result.artifact_run_directory
      }
    end

    def cache_summary(result)
      {
        "configured" => result.cache_configured_count,
        "hits" => result.cache_hit_count,
        "exact_hits" => result.cache_exact_hit_count,
        "fallback_hits" => result.cache_fallback_hit_count,
        "misses" => result.cache_miss_count,
        "saves" => result.cache_save_count,
        "warnings" => result.cache_warning_count
      }
    end
  end
end
