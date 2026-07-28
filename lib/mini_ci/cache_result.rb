# frozen_string_literal: true

module MiniCi
  class CacheResult
    attr_reader :configured,
                :disabled,
                :resolved_key,
                :restore_status,
                :restore_source_key,
                :restore_duration,
                :save_duration,
                :restored_file_count,
                :saved_file_count,
                :restored_size_bytes,
                :saved_size_bytes,
                :warnings,
                :errors

    def initialize(
      configured: false,
      disabled: false,
      resolved_key: nil,
      restore_status: :not_configured,
      restore_source_key: nil,
      restore_duration: 0,
      save_duration: 0,
      restored_file_count: 0,
      saved_file_count: 0,
      restored_size_bytes: 0,
      saved_size_bytes: 0,
      warnings: [],
      errors: []
    )
      @configured = configured
      @disabled = disabled
      @resolved_key = resolved_key
      @restore_status = restore_status
      @restore_source_key = restore_source_key
      @restore_duration = restore_duration
      @save_duration = save_duration
      @restored_file_count = restored_file_count
      @saved_file_count = saved_file_count
      @restored_size_bytes = restored_size_bytes
      @saved_size_bytes = saved_size_bytes
      @warnings = warnings.dup.freeze
      @errors = errors.dup.freeze
      freeze
    end

    def configured?
      configured
    end

    def disabled?
      disabled
    end

    def exact_hit?
      restore_status == :exact_hit
    end

    def fallback_hit?
      restore_status == :fallback_hit
    end

    def miss?
      restore_status == :miss
    end

    def restored?
      exact_hit? || fallback_hit?
    end

    def saved?
      saved_file_count.positive?
    end

    def failed?
      errors.any?
    end

    def merge_save(saved_file_count:, saved_size_bytes:, save_duration:, warnings:)
      self.class.new(
        configured: configured,
        disabled: disabled,
        resolved_key: resolved_key,
        restore_status: restore_status,
        restore_source_key: restore_source_key,
        restore_duration: restore_duration,
        restored_file_count: restored_file_count,
        restored_size_bytes: restored_size_bytes,
        saved_file_count: saved_file_count,
        saved_size_bytes: saved_size_bytes,
        save_duration: save_duration,
        warnings: self.warnings + warnings,
        errors: errors
      )
    end
  end
end
