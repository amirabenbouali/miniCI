# frozen_string_literal: true

require "fileutils"
require "rake/clean"
require "rspec/core/rake_task"
require "rubocop/rake_task"

require_relative "lib/mini_ci/version"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new(:rubocop)

task :syntax do
  ruby_files = FileList["lib/**/*.rb", "spec/**/*.rb", "bin/mini-ci", "Rakefile", "mini_ci.gemspec"]
  ruby_files.each { |file| sh "ruby", "-c", file }
end

task :build do
  sh "gem", "build", "mini_ci.gemspec"
  FileUtils.mkdir_p("pkg")
  gem_file = "mini_ci-#{MiniCi::VERSION}.gem"
  FileUtils.mv(gem_file, File.join("pkg", gem_file), force: true)
end

task install: :build do
  sh "gem", "install", File.join("pkg", "mini_ci-#{MiniCi::VERSION}.gem")
end

namespace :release do
  task check: %i[syntax rubocop spec build] do
    sh "gem", "specification", File.join("pkg", "mini_ci-#{MiniCi::VERSION}.gem"), "name"
    sh "bundle", "exec", "bin/mini-ci", "version"
    sh "bundle", "exec", "bin/mini-ci", "validate", "examples/showcase-pipeline.yml"
  end
end

CLEAN.include("mini_ci-*.gem")
CLOBBER.include("pkg")

task default: %i[spec rubocop]
