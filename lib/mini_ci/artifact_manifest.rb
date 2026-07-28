# frozen_string_literal: true

require "json"
require "time"

module MiniCi
  class ArtifactManifest
    def initialize(store:)
      @store = store
    end

    def write_for_pipeline(pipeline_result, pipeline_name:)
      payload = base_payload(pipeline_name, pipeline_result.success?)
      payload["jobs"] = [job_payload(index: 1, name: pipeline_name, result: pipeline_result)]
      write(payload)
    end

    def write_for_matrix(matrix_result, pipeline_name:)
      payload = base_payload(pipeline_name, matrix_result.success?)
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
          next unless artifact || cache

          item_payload = {
            "phase" => item_result.category.to_s,
            "index" => item_index + 1,
            "name" => item_result.step.name
          }
          if artifact
            item_payload.merge!(
            "artifact_directory" => artifact.destination ? @store.relative_to_run(artifact.destination) : nil,
            "files" => artifact.copied_file_count,
            "warnings" => artifact.warnings
            )
          end
          item_payload["cache"] = cache_payload(cache) if cache
          item_payload
        end.compact
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
