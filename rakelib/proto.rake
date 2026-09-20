# frozen_string_literal: true

namespace :proto do
  desc "Regenerate Ruby code for buf.validate (lib/) and the spec protos (spec/gen/)"
  task :generate do
    version = "v#{Protovalidate::PROTOVALIDATE_VERSION}"
    sh "buf", "generate", "buf.build/bufbuild/protovalidate:#{version}", "--template", "buf.gen.yaml"
    Dir.chdir("spec/proto") do
      sh "buf", "dep", "update"
      sh "buf", "generate", "--template", "buf.gen.yaml"
      sh "buf", "generate", "buf.build/bufbuild/protovalidate-testing:#{version}",
        "--template", "buf.gen.yaml", "--path", "buf/validate/conformance/harness"
    end
  end
end
