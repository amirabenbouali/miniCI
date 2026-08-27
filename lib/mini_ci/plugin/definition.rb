# frozen_string_literal: true

module MiniCi
  module Plugin
    class Definition
      NAME_PATTERN = /\A[a-z0-9][a-z0-9_-]*\z/
      CALLBACK_EVENTS = %i[
        before_run
        after_run
        before_pipeline
        after_pipeline
        before_matrix_job
        after_matrix_job
        before_item
        after_item
        before_cache_restore
        after_cache_restore
        before_cache_save
        after_cache_save
        before_artifact_collection
        after_artifact_collection
        after_report
      ].freeze

      attr_reader :name, :version, :description, :author, :homepage, :api_version, :source_path

      def initialize(name:, version:, description: nil, author: nil, homepage: nil, api_version: PLUGIN_API_VERSION,
                     source_path: nil)
        @name = validate_name(name)
        @version = validate_version(version, @name)
        @description = description
        @author = author
        @homepage = homepage
        @api_version = validate_api_version(api_version, @name)
        @source_path = source_path
        @callbacks = Hash.new { |callbacks, event| callbacks[event] = [] }
        @validators = []
        @item_types = []
      end

      CALLBACK_EVENTS.each do |event|
        define_method(event) do |serial: false, &block|
          register_callback(event, serial: serial, &block)
        end
      end

      def validate_configuration(&block)
        raise PluginRegistrationError, "Plugin registration failed: validator requires a block" unless block

        @validators << block
      end

      def register_item_type(name, validate: nil, &block)
        raise PluginRegistrationError, "Plugin registration failed: item type requires a block" unless block

        item_type_name = validate_item_type_name(name)
        @item_types << Plugin::ItemType.new(
          name: item_type_name,
          plugin: self,
          validator: validate,
          executor: block
        )
      end

      def callbacks_for(event)
        @callbacks[event.to_sym].dup.freeze
      end

      def validators
        @validators.dup.freeze
      end

      def item_types
        @item_types.dup.freeze
      end

      def metadata
        {
          "name" => name,
          "version" => version,
          "description" => description,
          "author" => author,
          "homepage" => homepage,
          "api_version" => api_version,
          "source" => source_path
        }.compact.freeze
      end

      def source_path=(path)
        @source_path ||= path
      end

      private

      def register_callback(event, serial:, &block)
        raise PluginRegistrationError, "Plugin registration failed: #{event} requires a block" unless block

        @callbacks[event] << Plugin::Callback.new(plugin: self, event: event, serial: serial, block: block)
      end

      def validate_name(value)
        unless value.is_a?(String) && value.match?(NAME_PATTERN)
          raise PluginRegistrationError, "Plugin registration failed: plugin name must match [a-z0-9][a-z0-9_-]*"
        end

        value
      end

      def validate_version(value, plugin_name)
        unless value.is_a?(String) && !value.strip.empty?
          raise PluginRegistrationError,
                %(Plugin registration failed: plugin "#{plugin_name}" version must be a non-empty string)
        end

        value
      end

      def validate_api_version(value, plugin_name)
        api = value || PLUGIN_API_VERSION
        unless api.to_s == PLUGIN_API_VERSION
          raise PluginRegistrationError,
                %(Plugin "#{plugin_name}" requires API version #{api}, but Mini CI supports version #{PLUGIN_API_VERSION})
        end

        api.to_s
      end

      def validate_item_type_name(value)
        validate_name(value)
      end
    end
  end
end
