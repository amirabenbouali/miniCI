# frozen_string_literal: true

require "pathname"

module MiniCi
  class ArtifactDefinition
    VALID_POLICIES = [:success, :failure, :always].freeze

    attr_reader :paths, :when_policy

    def initialize(paths:, when_policy: :always)
      @paths = validate_paths(paths)
      @when_policy = validate_when_policy(when_policy)
      freeze
    end

    def collect_on_success?
      when_policy == :success || always?
    end

    def collect_on_failure?
      when_policy == :failure || always?
    end

    def always?
      when_policy == :always
    end

    private

    def validate_paths(paths)
      unless paths.is_a?(Array) && !paths.empty?
        raise ArgumentError, "Artifact paths must be a non-empty array"
      end

      paths.map do |path|
        validate_path(path)
      end.freeze
    end

    def validate_path(path)
      unless path.is_a?(String) && !path.strip.empty?
        raise ArgumentError, "Artifact path must be a non-empty string"
      end

      if Pathname.new(path).absolute? || path.split(/[\\\/]+/).include?("..")
        raise ArgumentError, "Artifact path must stay inside the workspace"
      end

      path
    end

    def validate_when_policy(value)
      policy = value.to_sym if value.respond_to?(:to_sym)
      return policy if VALID_POLICIES.include?(policy)

      raise ArgumentError, "Artifact when policy must be one of success, failure, always"
    end
  end
end
