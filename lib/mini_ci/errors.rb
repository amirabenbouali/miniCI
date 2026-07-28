# frozen_string_literal: true

module MiniCi
  class Error < StandardError; end

  class ConfigurationError < Error; end

  class FileNotFoundError < Error; end

  class UsageError < Error; end

  class InternalError < Error; end

  class PluginError < Error; end

  class PluginRegistrationError < PluginError; end

  class PluginLoadError < PluginError; end
end
