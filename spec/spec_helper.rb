# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "mini_ci"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end
end
