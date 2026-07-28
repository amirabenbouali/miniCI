# frozen_string_literal: true

module MiniCi
  class PluginFailure
    attr_reader :plugin_name, :plugin_version, :event, :message, :exception_class, :backtrace

    def initialize(plugin_name:, plugin_version:, event:, message:, exception_class: nil, backtrace: [])
      @plugin_name = plugin_name
      @plugin_version = plugin_version
      @event = event
      @message = message
      @exception_class = exception_class
      @backtrace = Array(backtrace).dup.freeze
      freeze
    end

    def summary
      %(Plugin "#{plugin_name}" failed during #{event}: #{message})
    end

    def to_h
      {
        "plugin" => plugin_name,
        "version" => plugin_version,
        "event" => event.to_s,
        "message" => message,
        "exception_class" => exception_class
      }
    end
  end
end

