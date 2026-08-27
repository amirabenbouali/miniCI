# frozen_string_literal: true

module MiniCi
  module Plugin
    class ItemResult
      attr_reader :success, :plugin_name, :item_type, :output, :metadata, :failure

      def initialize(success:, plugin_name:, item_type:, output: nil, metadata: {}, failure: nil)
        @success = success
        @plugin_name = plugin_name
        @item_type = item_type
        @output = output
        @metadata = validate_metadata(metadata)
        @failure = failure
        freeze
      end

      def success?
        @success
      end

      def passed?
        success?
      end

      def failed?
        !success?
      end

      def skipped?
        false
      end

      def duration
        0
      end

      private

      def validate_metadata(value)
        Plugin::MetadataBuilder.new.tap do |builder|
          value.each { |key, child| builder[key] = child }
        end.to_h
      end
    end
  end
end
