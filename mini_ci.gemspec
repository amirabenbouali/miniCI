# frozen_string_literal: true

require_relative "lib/mini_ci/version"

Gem::Specification.new do |spec|
  spec.name = "mini_ci"
  spec.version = MiniCi::VERSION
  spec.authors = ["Amira Benbouali"]
  spec.summary = "A lightweight local CI-style pipeline runner."
  spec.description = "Mini CI runs YAML-defined development pipelines locally with hooks, retries, timeouts, matrix jobs, artifacts, caching, plugins, run history, and a local dashboard."
  spec.homepage = "https://github.com/amirabenbouali/miniCI"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "#{spec.homepage}/tree/main",
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues"
  }

  spec.files = Dir[
    "bin/mini-ci",
    "examples/**/*.yml",
    "lib/**/*.rb",
    "public/**/*",
    "scripts/*.sh",
    "views/**/*",
    "README.md",
    "CHANGELOG.md",
    "LICENSE",
    "SECURITY.md",
    "CODE_OF_CONDUCT.md",
    "CONTRIBUTING.md",
    "docs/**/*.md"
  ].select { |path| File.file?(path) }
  spec.bindir = "bin"
  spec.executables = ["mini-ci"]
  spec.require_paths = ["lib"]

  spec.add_dependency "rackup", "~> 2.2"
  spec.add_dependency "sinatra", "~> 4.1"
  spec.add_dependency "webrick", "~> 1.8"

  spec.add_development_dependency "rack-test", "~> 2.1"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.13"
end
