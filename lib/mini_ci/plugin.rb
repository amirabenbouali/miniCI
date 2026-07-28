# frozen_string_literal: true

require_relative "plugin/callback"
require_relative "plugin/context"
require_relative "plugin/definition"
require_relative "plugin/failure"
require_relative "plugin/item_result"
require_relative "plugin/item_type"
require_relative "plugin/loader"
require_relative "plugin/metadata_builder"
require_relative "plugin/registry"
require_relative "plugin/runner"

module MiniCi
  PLUGIN_API_VERSION = "1"

  module Plugin
    class << self
      def registry
        @registry ||= Registry.new
      end

      def register(definition = nil, **metadata)
        if definition
          registry.register(definition)
        else
          plugin = Definition.new(**metadata)
          yield plugin if block_given?
          registry.register(plugin)
        end
      end

      def reset!
        registry.reset!
      end
    end
  end
end
