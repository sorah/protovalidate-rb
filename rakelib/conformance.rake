# frozen_string_literal: true

desc "Run the protovalidate conformance suite (SUITE= and CASE= filter by regexp)"
task conformance: :compile do
  version = "v#{Protovalidate::PROTOVALIDATE_VERSION}"
  harness = ENV["PROTOVALIDATE_CONFORMANCE"] || conformance_harness(version)
  args = [
    harness,
    "--strict_message",
    "--timeout", ENV.fetch("CONFORMANCE_TIMEOUT", "10s"),
    "--expected_failures", "spec/conformance/expected_failures.yaml",
  ]
  args += ["--suite", ENV.fetch("SUITE")] if ENV["SUITE"]
  args += ["--case", ENV.fetch("CASE")] if ENV["CASE"]
  args << "--verbose" if ENV["VERBOSE"]
  sh(*args, "bundle", "exec", "ruby", "spec/conformance/executor.rb")
end

# Installs the harness pinned to the bundled protovalidate version into tmp/bin.
def conformance_harness(version)
  path = File.expand_path("../tmp/bin/protovalidate-conformance", __dir__)
  unless File.executable?(path)
    sh({"GOBIN" => File.dirname(path)}, "go", "install",
      "github.com/bufbuild/protovalidate/tools/protovalidate-conformance@#{version}")
  end
  path
end
