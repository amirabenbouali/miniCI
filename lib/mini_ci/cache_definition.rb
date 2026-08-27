# frozen_string_literal: true

require "pathname"

module MiniCi
  class CacheDefinition
    VALID_SAVE_POLICIES = %i[success always].freeze

    attr_reader :key, :paths, :restore_keys, :save_when

    def initialize(key:, paths:, restore_keys: [], save_when: :success)
      @key = validate_key(key, "cache key")
      @paths = validate_paths(paths)
      @restore_keys = validate_restore_keys(restore_keys)
      @save_when = validate_save_when(save_when)
      freeze
    end

    def save_on_success?
      %i[success always].include?(save_when)
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
      raise ArgumentError, "cache paths must be a non-empty array" unless value.is_a?(Array) && !value.empty?

      value.map { |path| validate_path(path) }.freeze
    end

    def validate_path(path)
      raise ArgumentError, "cache path must be a non-empty string" unless path.is_a?(String) && !path.strip.empty?

      if Pathname.new(path).absolute? || path.split(%r{[\\/]+}).include?("..")
        raise ArgumentError, "cache path must stay inside the workspace"
      end

      path
    end

    def validate_restore_keys(value)
      raise ArgumentError, "cache restore_keys must be an array" unless value.is_a?(Array)

      value.map { |key| validate_key(key, "cache restore key") }.freeze
    end

    def validate_save_when(value)
      policy = value.to_sym if value.respond_to?(:to_sym)
      return policy if VALID_SAVE_POLICIES.include?(policy)

      raise ArgumentError, "cache save_when must be one of success, always"
    end
  end
end
