# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "mini_ci"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end
end

# Simulates running Mini CI in an environment without a UTF-8 locale
# (e.g. LANG/LC_ALL unset), where Encoding.default_external falls back
# to US-ASCII. Ensures any code reading raw bytes into a String tags it
# correctly rather than inheriting the ambient default.
def with_default_external_encoding(name)
  original = Encoding.default_external
  Encoding.default_external = name
  yield
ensure
  Encoding.default_external = original
end
