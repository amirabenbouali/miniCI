# frozen_string_literal: true

require "tempfile"

module MiniCi
  class BufferedJobOutput
    attr_reader :io

    def initialize
      @io = Tempfile.new("mini-ci-matrix-job")
      @io.set_encoding(Encoding::UTF_8)
    end

    def string
      @io.flush
      @io.rewind
      @io.read.scrub
    end

    def close
      @io.close!
    end
  end
end
