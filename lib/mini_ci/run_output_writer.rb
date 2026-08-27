# frozen_string_literal: true

require "fileutils"

module MiniCi
  class RunOutputWriter
    MAX_READ_BYTES = 64 * 1024

    def initialize(path)
      @path = path
      @mutex = Mutex.new
      FileUtils.mkdir_p(File.dirname(path))
      FileUtils.touch(path)
    end

    attr_reader :path

    def write(value)
      text = value.to_s
      @mutex.synchronize do
        File.open(@path, "ab") { |file| file.write(text) }
      end
      text.length
    end

    def <<(value)
      write(value)
      self
    end

    def puts(*values)
      values = [""] if values.empty?
      values.each { |value| write("#{value}\n") }
      nil
    end

    def print(*values)
      values.each { |value| write(value) }
      nil
    end

    def flush; end

    def read_tail(offset:, limit: MAX_READ_BYTES)
      safe_offset = [offset.to_i, 0].max
      File.open(@path, "rb") do |file|
        file.seek(safe_offset)
        text = file.read([limit.to_i, MAX_READ_BYTES].min) || ""
        { "text" => text, "next_offset" => file.pos, "complete" => file.eof? }
      end
    rescue Errno::ENOENT
      { "text" => "", "next_offset" => 0, "complete" => true }
    end
  end

  class TeeOutput
    def initialize(*targets)
      @targets = targets.compact
      @mutex = Mutex.new
    end

    def write(value)
      @mutex.synchronize { @targets.each { |target| target.write(value) } }
      value.to_s.length
    end

    def <<(value)
      write(value)
      self
    end

    def puts(*values)
      values = [""] if values.empty?
      values.each { |value| write("#{value}\n") }
      nil
    end

    def print(*values)
      values.each { |value| write(value) }
      nil
    end

    def flush
      @targets.each { |target| target.flush if target.respond_to?(:flush) }
    end
  end
end
