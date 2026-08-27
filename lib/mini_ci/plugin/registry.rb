# frozen_string_literal: true

module MiniCi
  module Plugin
    class Registry
      attr_reader :loaded_files

      def initialize
        @plugins = []
        @plugins_by_name = {}
        @item_types = {}
        @loaded_files = {}
        @frozen = false
      end

      def register(plugin)
        ensure_mutable!
        unless plugin.is_a?(Plugin::Definition)
          raise PluginRegistrationError, "Plugin registration failed: expected a plugin definition"
        end
        if registered?(plugin.name)
          raise PluginRegistrationError, %(Plugin registration failed: plugin "#{plugin.name}" is already registered)
        end

        @plugins << plugin
        @plugins_by_name[plugin.name] = plugin
        plugin.item_types.each do |item_type|
          if @item_types.key?(item_type.name)
            raise PluginRegistrationError,
                  %(Plugin registration failed: item type "#{item_type.name}" is already registered)
          end

          @item_types[item_type.name] = item_type
        end
        plugin
      end

      def plugins
        @plugins.dup.freeze
      end

      def find(name)
        @plugins_by_name[name]
      end

      def registered?(name)
        @plugins_by_name.key?(name)
      end

      def callbacks_for(event)
        @plugins.flat_map { |plugin| plugin.callbacks_for(event) }.freeze
      end

      def validators
        @plugins.flat_map { |plugin| plugin.validators.map { |validator| [plugin, validator] } }.freeze
      end

      def item_types
        @item_types.dup.freeze
      end

      def item_type(name)
        @item_types[name]
      end

      def mark_loaded(path)
        @loaded_files[path] = true
      end

      def loaded?(path)
        @loaded_files.key?(path)
      end

      def freeze!
        @frozen = true
        plugins.each(&:freeze)
        self
      end

      def frozen?
        @frozen
      end

      def reset!
        @plugins.clear
        @plugins_by_name.clear
        @item_types.clear
        @loaded_files.clear
        @frozen = false
      end

      private

      def ensure_mutable!
        return unless frozen?

        raise PluginRegistrationError, "Plugin registration failed: registry is frozen"
      end
    end
  end
end
