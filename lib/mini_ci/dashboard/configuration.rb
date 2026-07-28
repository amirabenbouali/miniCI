# frozen_string_literal: true

module MiniCi
  module Dashboard
    class Configuration
      attr_reader :host, :port, :max_runs, :open_browser

      def initialize(host: "127.0.0.1", port: 4567, max_runs: 200, open_browser: false)
        @host = host
        @port = Integer(port)
        @max_runs = Integer(max_runs)
        @open_browser = open_browser
        validate!
      end

      def non_loopback?
        !["127.0.0.1", "localhost", "::1"].include?(host)
      end

      private

      def validate!
        raise UsageError, "dashboard port must be between 1 and 65535" unless (1..65_535).cover?(port)
        raise UsageError, "dashboard max-runs must be positive" unless max_runs.positive?
      end
    end
  end
end

