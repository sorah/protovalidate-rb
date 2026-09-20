# frozen_string_literal: true

# Executor for the protovalidate conformance harness. Reads one serialized
# TestConformanceRequest from stdin, validates every case with the gem exactly
# as an application would, and writes a TestConformanceResponse to stdout.

$LOAD_PATH.unshift(File.expand_path("../../lib", __dir__), File.expand_path("../gen", __dir__))

require "protovalidate"
require "buf/validate/conformance/harness/harness_pb"

module ConformanceExecutor
  Harness = Buf::Validate::Conformance::Harness

  module_function def run(input)
    request = Harness::TestConformanceRequest.decode(input)
    pool = Google::Protobuf::DescriptorPool.new
    # The harness orders the set with imports first, which add_serialized_file requires.
    request.fdset.file.each do |file|
      pool.add_serialized_file(Google::Protobuf::FileDescriptorProto.encode(file))
    end
    validator = Protovalidate::Validator.new(descriptor_pool: pool)

    response = Harness::TestConformanceResponse.new
    request.cases.each do |name, any|
      response.results[name] = run_case(validator, pool, any)
    end
    Harness::TestConformanceResponse.encode(response)
  end

  module_function def run_case(validator, pool, any)
    type_name = any.type_url.split("/").last
    descriptor = pool.lookup(type_name)
    unless descriptor.is_a?(Google::Protobuf::Descriptor)
      return Harness::TestResult.new(unexpected_error: "unknown type: #{type_name}")
    end

    message = descriptor.msgclass.decode(any.value)
    violations = validator.collect_violations(message)
    if violations.empty?
      Harness::TestResult.new(success: true)
    else
      Harness::TestResult.new(
        validation_error: Buf::Validate::Violations.new(violations: violations.map(&:proto)),
      )
    end
  rescue Protovalidate::CompilationError => e
    Harness::TestResult.new(compilation_error: e.message)
  rescue Protovalidate::EvaluationError => e
    Harness::TestResult.new(runtime_error: e.message)
  rescue StandardError => e
    Harness::TestResult.new(unexpected_error: "#{e.class}: #{e.message}")
  end
end

if $PROGRAM_NAME == __FILE__
  $stdin.binmode
  $stdout.binmode
  $stdout.write(ConformanceExecutor.run($stdin.read))
  $stdout.flush
end
