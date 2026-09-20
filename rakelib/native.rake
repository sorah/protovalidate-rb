# frozen_string_literal: true

require "rubygems/package"

# Ruby minors a precompiled gem carries; the fat loader in
# lib/protovalidate/native.rb picks the matching directory at require time.
NATIVE_RUBY_MINORS = %w[3.3 3.4 4.0].freeze

namespace :gem do
  desc "Build a precompiled gem for PLATFORM from lib/protovalidate/<X.Y>/ extensions"
  task :native, [:platform] do |_, args|
    platform = args.fetch(:platform) { abort "usage: rake 'gem:native[x86_64-linux-gnu]'" }
    binaries = NATIVE_RUBY_MINORS.flat_map do |minor|
      Dir["lib/protovalidate/#{minor}/protovalidate_native.{so,bundle}"]
    end
    missing = NATIVE_RUBY_MINORS.reject { |minor| binaries.any? { |b| b.include?("/#{minor}/") } }
    abort "missing extensions for Ruby #{missing.join(", ")}" unless missing.empty?

    licenses = bundle_third_party_licenses

    spec = GEMSPEC.dup
    spec.platform = Gem::Platform.new(platform)
    spec.files = spec.files.reject { |f| f.start_with?("ext/") } + binaries + licenses
    spec.extensions = []
    spec.dependencies.delete_if { |dependency| dependency.name == "rb_sys" }
    # Newer Ruby minors have no binary here and fall back to the source gem.
    last = NATIVE_RUBY_MINORS.last.split(".").map(&:to_i)
    spec.required_ruby_version = [">= #{NATIVE_RUBY_MINORS.first}", "< #{last[0]}.#{last[1] + 1}.dev"]

    mkdir_p "pkg"
    path = Gem::Package.build(spec)
    mv path, "pkg/#{path}"
    puts "built pkg/#{path}"
  end
end

# Precompiled gems drop ext/, so the licenses of the compiled-in third-party
# code travel under licenses/ instead.
def bundle_third_party_licenses
  rm_rf "licenses"
  mkdir_p "licenses"
  Dir["ext/protovalidate/sys/third_party/*/LICENSE*"].sort.map do |source|
    project = File.basename(File.dirname(source))
    target = "licenses/#{project}-#{File.basename(source)}"
    cp source, target
    target
  end
end

# bundler's release task pushes only the source gem; precompiled gems staged
# in pkg/ by the release workflow are pushed alongside it.
Rake::Task["release:rubygem_push"].enhance do
  Dir["pkg/#{GEMSPEC.name}-#{GEMSPEC.version}-*.gem"].sort.each do |gem|
    sh "gem", "push", gem
  end
end
