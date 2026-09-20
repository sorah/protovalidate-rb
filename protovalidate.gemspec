# frozen_string_literal: true

require_relative "lib/protovalidate/version"

Gem::Specification.new do |spec|
  spec.name = "protovalidate"
  spec.version = Protovalidate::VERSION
  spec.authors = ["Sorah Fukumori"]
  spec.email = ["sorah@ivry.jp"]

  spec.summary = "Protobuf message validation with protovalidate (buf.validate) rules"
  spec.description = "Ruby implementation of protovalidate. Validates Protobuf messages against the " \
    "buf.validate rules in their schema, evaluated with CEL by protovalidate-cc through a native " \
    "extension. Precompiled gems are published for Linux and macOS."
  spec.homepage = "https://github.com/sorah/protovalidate-rb"
  spec.license = "Apache-2.0"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  gemspec = File.basename(__FILE__)
  dev_only = %w[
    bin/ spec/ sig-stub/ script/ rakelib/ .github/ tmp/ pkg/ mise.lock
    Gemfile .gitignore .gitmodules .rspec .rubocop.yml .ruby-version
    Steepfile rbs_collection hk.pkl mise.toml buf.gen
  ]
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      f == gemspec || f.start_with?(*dev_only) || File.directory?(File.join(__dir__, f))
    end
  end

  # Vendored C++ sources live in git submodules, which `git ls-files` lists as
  # bare directory entries. Ship exactly the sources the extension compiles
  # (from the generated file lists) plus the headers under each include root.
  sys = "ext/protovalidate/sys"
  compiled = Dir.glob("#{sys}/filelists/*.txt", base: __dir__).flat_map do |list|
    File.readlines(File.join(__dir__, list), chomp: true).filter_map do |line|
      next if line.empty? || line.start_with?("#")

      "#{sys}/#{line.sub(/\A(?:windows|linux|macos):/, "")}"
    end
  end
  include_roots = %w[
    abseil-cpp/absl
    antlr4/runtime/Cpp/runtime/src
    cel-cpp
    protobuf/src/google
    protobuf/third_party/utf8_range
    re2/re2
    re2/util
    protovalidate-cc/buf
  ]
  headers = include_roots.flat_map do |root|
    Dir.glob("#{sys}/third_party/#{root}/**/*.{h,hpp,inc,def}", base: __dir__)
  end
  headers.reject! { |f| f.match?(%r{/(test|tests|testing|testdata|testutil|benchmark|benchmarks|conformance)/|_test\.h\z}) }
  # The importer and parser under protobuf's compiler/ are compiled; the
  # per-language generators in its subdirectories are not.
  headers.reject! { |f| f.match?(%r{/protobuf/src/google/protobuf/compiler/[^/]+/}) }
  licenses = Dir.glob("#{sys}/third_party/*/LICENSE*", base: __dir__)
  spec.files += (compiled + headers + licenses).uniq.select { |f| File.file?(File.join(__dir__, f)) }

  spec.require_paths = ["lib"]
  spec.extensions = ["ext/protovalidate/extconf.rb"]

  spec.add_dependency "google-protobuf", ">= 4.31"
  spec.add_dependency "rb_sys", "~> 0.9.130"
end
