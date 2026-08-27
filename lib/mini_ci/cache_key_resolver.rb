# frozen_string_literal: true

require "digest"
require "pathname"

module MiniCi
  class CacheKeyResolver
    MAX_KEY_LENGTH = 512
    INTERPOLATION = /\$\{\{\s*(.*?)\s*\}\}/

    def initialize(workspace:)
      @workspace = Pathname.new(workspace).realpath
    end

    def resolve(template, env:)
      resolved = template.gsub(INTERPOLATION) do
        expression = Regexp.last_match(1)
        evaluate(expression, env)
      end

      validate_resolved_key(resolved)
      resolved
    end

    def validate_template!(template)
      template.scan(INTERPOLATION).flatten.each { |expression| parse_expression(expression) }
    end

    private

    def evaluate(expression, env)
      type, value = parse_expression(expression)
      case type
      when :env
        env.fetch(value, "")
      when :checksum
        checksum(value)
      end
    end

    def parse_expression(expression)
      stripped = expression.strip
      if (match = stripped.match(/\Aenv\.([A-Za-z_][A-Za-z0-9_]*)\z/))
        [:env, match[1]]
      elsif (match = stripped.match(/\Achecksum\("([^"]+)"\)\z/))
        [:checksum, match[1]]
      else
        raise ConfigurationError,
              "Invalid pipeline configuration: cache key has unsupported expression #{expression.inspect}"
      end
    end

    def checksum(path)
      if Pathname.new(path).absolute? || path.split(%r{[\\/]+}).include?("..")
        raise ConfigurationError,
              "Cache key resolution failed: checksum path #{path.inspect} must stay inside the workspace"
      end

      full_path = Pathname.new(File.join(@workspace.to_s, path))
      real_path = full_path.realpath
      unless real_path.to_s.start_with?("#{@workspace}/") || real_path.to_s == @workspace.to_s
        raise ConfigurationError,
              "Cache key resolution failed: checksum file #{path.inspect} resolves outside the workspace"
      end
      if File.directory?(real_path)
        raise ConfigurationError, "Cache key resolution failed: checksum file #{path.inspect} is a directory"
      end

      Digest::SHA256.file(real_path.to_s).hexdigest
    rescue Errno::ENOENT
      raise ConfigurationError, "Cache key resolution failed: checksum file #{path.inspect} does not exist"
    end

    def validate_resolved_key(key)
      if key.empty? || key.include?("\0")
        raise ConfigurationError, "Cache key resolution failed: resolved cache key must be non-empty"
      end
      return unless key.length > MAX_KEY_LENGTH

      raise ConfigurationError, "Cache key resolution failed: resolved cache key exceeds #{MAX_KEY_LENGTH} characters"
    end
  end
end
