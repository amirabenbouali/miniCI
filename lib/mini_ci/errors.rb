# frozen_string_literal: true

module MiniCi
  class Error < StandardError; end

  class ConfigurationError < Error; end

  class FileNotFoundError < Error; end
end
