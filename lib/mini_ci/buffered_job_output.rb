# frozen_string_literal: true

require "tempfile"

module MiniCi
  class BufferedJobOutput
    attr_reader :io

    def initialize
      @io = Tempfile.new("mini-ci-matrix-job")
    end

    def string
      @io.flush
      @io.rewind
      @io.read
    end

    def close
      @io.close!
    end
  end
end
