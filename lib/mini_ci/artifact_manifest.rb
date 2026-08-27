# frozen_string_literal: true

require "json"
require "time"

require_relative "plugin"

module MiniCi
  class ArtifactManifest
    def initialize(store:, plugin_registry: Plugin.registry, plugin_metadata: nil, plugin_failures: [])
      @store = store
      @plugin_registry = plugin_registry
      @plugin_metadata = plugin_metadata
      @plugin_failures = plugin_failures.compact
    end

    def write_for_pipeline(pipeline_result, pipeline_name:, overall_success: nil)
      payload = base_payload(pipeline_name, overall_success.nil? ? pipeline_result.success? : overall_success)
      payload["jobs"] = [job_payload(index: 1, name: pipeline_name, result: pipeline_result)]
      write(payload)
    end

    def write_for_matrix(matrix_result, pipeline_name:, overall_success: nil)
      payload = base_payload(pipeline_name, overall_success.nil? ? matrix_result.success? : overall_success)
      payload["jobs"] = matrix_result.matrix_job_results.each_with_index.map do |job_result, index|
        job_payload(index: index + 1, name: job_result.display_name, result: job_result.pipeline_result)
      end
      write(payload)
    end

    private

    def base_payload(pipeline_name, success)
      {
        "run_id" => @store.run_id,
        "pipeline" => pipeline_name,
        "status" => success ? "passed" : "failed",
        "started_at" => @store.started_at.iso8601,
        "finished_at" => Time.now.utc.iso8601,
        "plugins" => @plugin_registry.plugins.map(&:metadata),
        "plugin_failures" => @plugin_failures.map(&:to_h),
        "plugin_metadata" => @plugin_metadata ? @plugin_metadata.to_h : {},
        "jobs" => []
      }
    end

    def job_payload(index:, name:, result:)
      {
        "index" => index,
        "name" => name,
        "status" => result.success? ? "passed" : "failed",
        "items" => result.all_results.each_with_index.map do |item_result, item_index|
          artifact = item_result.artifact_result
          cache = item_result.cache_result
          plugin_item = item_result.plugin_item_result
          plugin_failure = item_result.plugin_failure
          next unless artifact || cache || plugin_item || plugin_failure

          item_payload = {
            "phase" => item_result.category.to_s,
            "index" => item_index + 1,
            "name" => item_result.step.name,
            "status" => item_result.success? ? "passed" : "failed"
          }
          if artifact
            item_payload.merge!(
              "artifact_directory" => artifact.destination ? @store.relative_to_run(artifact.destination) : nil,
              "files" => artifact.copied_file_count,
              "warnings" => artifact.warnings
            )
          end
          item_payload["cache"] = cache_payload(cache) if cache
          item_payload["plugin"] = plugin_item_payload(plugin_item) if plugin_item
          item_payload["plugin_failure"] = plugin_failure.to_h if plugin_failure
          item_payload
        end.compact
      }
    end

    def plugin_item_payload(plugin_item)
      {
        "type" => "plugin",
        "plugin" => plugin_item.plugin_name,
        "uses" => plugin_item.item_type,
        "status" => plugin_item.success? ? "passed" : "failed",
        "metadata" => plugin_item.metadata
      }
    end

    def cache_payload(cache)
      {
        "resolved_key" => cache.resolved_key,
        "restore_status" => cache.restore_status.to_s,
        "restore_source_key" => cache.restore_source_key,
        "restored_files" => cache.restored_file_count,
        "saved_files" => cache.saved_file_count,
        "warnings" => cache.warnings,
        "errors" => cache.errors
      }
    end

    def write(payload)
      File.write(File.join(@store.run_directory, "manifest.json"), JSON.pretty_generate(payload))
    rescue SystemCallError => e
      raise InternalError, "artifact manifest could not be written: #{e.message}"
    end
  end
end
