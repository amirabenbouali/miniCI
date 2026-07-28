# frozen_string_literal: true

require "pathname"

module MiniCi
  class CacheDefinition
    VALID_SAVE_POLICIES = [:success, :always].freeze

    attr_reader :key, :paths, :restore_keys, :save_when

    def initialize(key:, paths:, restore_keys: [], save_when: :success)
      @key = validate_key(key, "cache key")
      @paths = validate_paths(paths)
      @restore_keys = validate_restore_keys(restore_keys)
      @save_when = validate_save_when(save_when)
      freeze
    end

    def save_on_success?
      save_when == :success || save_when == :always
    end

    def save_on_failure?
      save_when == :always
    end

    private

    def validate_key(value, label)
      unless value.is_a?(String) && !value.strip.empty? && !value.include?("\0")
        raise ArgumentError, "#{label} must be a non-empty string"
      end

      value
    end

    def validate_paths(value)
      unless value.is_a?(Array) && !value.empty?
        raise ArgumentError, "cache paths must be a non-empty array"
      end

      value.map { |path| validate_path(path) }.freeze
    end

    def validate_path(path)
      unless path.is_a?(String) && !path.strip.empty?
        raise ArgumentError, "cache path must be a non-empty string"
      end

      if Pathname.new(path).absolute? || path.split(/[\\\/]+/).include?("..")
        raise ArgumentError, "cache path must stay inside the workspace"
      end

      path
    end

    def validate_restore_keys(value)
      unless value.is_a?(Array)
        raise ArgumentError, "cache restore_keys must be an array"
      end

      value.map { |key| validate_key(key, "cache restore key") }.freeze
    end

    def validate_save_when(value)
      policy = value.to_sym if value.respond_to?(:to_sym)
      return policy if VALID_SAVE_POLICIES.include?(policy)

      raise ArgumentError, "cache save_when must be one of success, always"
    end
  end
end
