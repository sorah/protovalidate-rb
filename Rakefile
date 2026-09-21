# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rake/extensiontask"

require_relative "lib/protovalidate/version"

GEMSPEC = Bundler.load_gemspec("protovalidate.gemspec")

# No gemspec: precompiled gems are assembled by rakelib/native.rake, and the
# source pattern stays narrow so rake does not walk the vendored submodules.
Rake::ExtensionTask.new("protovalidate_native") do |ext|
  ext.ext_dir = "ext/protovalidate"
  ext.lib_dir = "lib/protovalidate"
  ext.source_pattern = "{Cargo.toml,Cargo.lock,build.rs,src/**/*.rs,sys/Cargo.toml,sys/build.rs,sys/src/**/*.rs,sys/shim/*,sys/filelists/*.txt}"
  # Platforms without a native CI runner are cross-compiled inside rb-sys-dock
  # images (see .github/workflows/native.yml). Given several RUBY_CC_VERSIONs,
  # `rake cross compile` stages each under tmp/<platform>/stage/lib/protovalidate/<X.Y>/.
  ext.cross_compile = true
  ext.cross_platform = %w[x86_64-linux-musl aarch64-linux-musl arm-linux-gnueabihf]
end

RSpec::Core::RakeTask.new(:spec)
task spec: :compile

desc "Typecheck lib/ against sig/ with steep"
task :steep do
  sh "bundle exec steep check"
end

desc "Lint with RuboCop"
task :rubocop do
  sh "bundle exec rubocop"
end

task default: :spec
