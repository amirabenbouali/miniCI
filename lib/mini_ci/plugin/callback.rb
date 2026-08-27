# frozen_string_literal: true

module MiniCi
  module Plugin
    class Callback
      attr_reader :plugin, :event

      def initialize(plugin:, event:, serial:, block:)
        @plugin = plugin
        @event = event
        @serial = serial
        @block = block
        @mutex = Mutex.new
        freeze
      end

      def call(context)
        if serial?
          @mutex.synchronize { @block.call(context) }
        else
          @block.call(context)
        end
      end

      def serial?
        @serial
      end
    end
  end
end
