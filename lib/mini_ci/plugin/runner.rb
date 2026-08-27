# frozen_string_literal: true

module MiniCi
  module Plugin
    class Runner
      def initialize(registry:)
        @registry = registry
      end

      def invoke(event, context)
        @registry.callbacks_for(event).each do |callback|
          callback.call(context)
        rescue StandardError => e
          return PluginFailure.new(
            plugin_name: callback.plugin.name,
            plugin_version: callback.plugin.version,
            event: event,
            message: e.message,
            exception_class: e.class.name,
            backtrace: e.backtrace
          )
        end
        nil
      end
    end
  end
end
