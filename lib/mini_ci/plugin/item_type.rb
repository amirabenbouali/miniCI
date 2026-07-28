# frozen_string_literal: true

module MiniCi
  module Plugin
    class ItemType
      attr_reader :name, :plugin, :validator

      def initialize(name:, plugin:, validator:, executor:)
        @name = name
        @plugin = plugin
        @validator = validator
        @executor = executor
        freeze
      end

      def validate(input)
        return [] unless @validator

        Array(@validator.call(input)).compact
      end

      def execute(input, context)
        result = @executor.call(input, context)
        return result if result.is_a?(Plugin::ItemResult)

        Plugin::ItemResult.new(
          success: result != false,
          plugin_name: plugin.name,
          item_type: name
        )
      end
    end
  end
end

