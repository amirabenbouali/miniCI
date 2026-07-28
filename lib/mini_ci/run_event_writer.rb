# frozen_string_literal: true

require "json"
require "fileutils"
require "time"
require "thread"

module MiniCi
  class RunEventWriter
    def initialize(path, clock: -> { Time.now.utc })
      @path = path
      @clock = clock
      @mutex = Mutex.new
      FileUtils.mkdir_p(File.dirname(path))
      FileUtils.touch(path)
    end

    def append(type, payload = {})
      event = stringify(payload).merge(
        "timestamp" => @clock.call.iso8601,
        "type" => type.to_s
      )
      @mutex.synchronize do
        File.open(@path, "ab") { |file| file.write("#{JSON.generate(event)}\n") }
      end
      event
    end

    def read(after: 0)
      cursor = [after.to_i, 0].max
      events = []
      File.readlines(@path).each_with_index do |line, index|
        next if index < cursor

        events << JSON.parse(line)
      rescue JSON::ParserError
        next
      end
      { "events" => events, "next_cursor" => cursor + events.length }
    rescue Errno::ENOENT
      { "events" => [], "next_cursor" => 0 }
    end

    private

    def stringify(value)
      case value
      when Hash
        value.each_with_object({}) { |(key, child), output| output[key.to_s] = stringify(child) }
      when Array
        value.map { |child| stringify(child) }
      when String, Integer, Float, TrueClass, FalseClass, NilClass
        value
      else
        value.to_s
      end
    end
  end
end
