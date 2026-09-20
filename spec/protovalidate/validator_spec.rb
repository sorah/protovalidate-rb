# frozen_string_literal: true

RSpec.describe Protovalidate::Validator do
  subject(:validator) { described_class.new }

  describe "#validate" do
    it "accepts a valid message" do
      expect(validator.validate(valid_user)).to be_nil
    end

    it "raises ValidationError with the same violations collect_violations returns" do
      message = valid_user(name: "", email: "not-an-email")
      collected = validator.collect_violations(message)
      expect { validator.validate(message) }.to raise_error(Protovalidate::ValidationError) do |error|
        expect(error.violations.map(&:proto)).to eq(collected.map(&:proto))
      end
    end

    it "raises TypeError for something that is not a message" do
      expect { validator.validate("not a message") }.to raise_error(TypeError, /expected a Google::Protobuf message/)
    end
  end

  describe "#collect_violations" do
    it "reports a scalar rule" do
      violation = validator.collect_violations(valid_user(name: "")).fetch(0)
      expect(violation.rule_id).to eq("string.min_len")
      expect(violation.field_path).to eq("name")
      expect(violation.message).to eq("must be at least 1 characters")
      expect(violation.for_key?).to be(false)
    end

    it "reports a nested message rule" do
      message = valid_user(address: ProtovalidateSpec::Address.new(city: ""))
      violation = validator.collect_violations(message).fetch(0)
      expect(violation.rule_id).to eq("string.min_len")
      expect(violation.field_path).to eq("address.city")
    end

    it "reports repeated items with their index" do
      violation = validator.collect_violations(valid_user(tags: ["ok", ""])).fetch(0)
      expect(violation.rule_id).to eq("string.min_len")
      expect(violation.field_path).to eq("tags[1]")
    end

    it "reports duplicate repeated items" do
      violations = validator.collect_violations(valid_user(tags: ["a", "a"]))
      expect(violations.map(&:rule_id)).to eq(["repeated.unique"])
    end

    it "reports map keys and values" do
      violations = validator.collect_violations(valid_user(scores: {"" => 1, "math" => -1}))
      expect(violations.map { |v| [v.rule_id, v.field_path, v.for_key?] }).to contain_exactly(
        ["string.min_len", 'scores[""]', true],
        ["int32.gte", 'scores["math"]', false],
      )
    end

    it "evaluates well-known type rules" do
      future = Google::Protobuf::Timestamp.from_time(Time.now + 3600)
      violations = validator.collect_violations(valid_user(created_at: future))
      expect(violations.map(&:rule_id)).to eq(["timestamp.lt_now"])
    end

    it "evaluates predefined rules declared as extensions" do
      violations = validator.collect_violations(valid_user(even: 3))
      expect(violations.map { |v| [v.rule_id, v.message, v.field_path] }).to eq([["int32.even", "must be even", "even"]])
    end

    it "evaluates message-level CEL rules" do
      violations = validator.collect_violations(valid_user(name: "admin"))
      expect(violations.map { |v| [v.rule_id, v.message, v.field_path] })
        .to eq([["user.name_not_admin", "name must not be admin", ""]])
      expect(violations.fetch(0).field).to be_nil
    end

    it "stops after the first violation with fail_fast" do
      message = valid_user(name: "", email: "x", age: -1)
      expect(validator.collect_violations(message, fail_fast: true).size).to eq(1)
      expect(validator.collect_violations(message).size).to eq(3)
    end

    it "raises CompilationError when a rule does not compile" do
      expect { validator.collect_violations(ProtovalidateSpec::BadRule.new(value: "x")) }
        .to raise_error(Protovalidate::CompilationError, /overload/i)
    end

    it "keeps raising CompilationError on later calls" do
      2.times do
        expect { validator.collect_violations(ProtovalidateSpec::BadRule.new) }
          .to raise_error(Protovalidate::CompilationError)
      end
    end

    it "raises EvaluationError when a rule fails during evaluation" do
      expect(validator.collect_violations(ProtovalidateSpec::RuntimeFailure.new(divisor: 1))).to eq([])
      expect { validator.collect_violations(ProtovalidateSpec::RuntimeFailure.new(divisor: 0)) }
        .to raise_error(Protovalidate::EvaluationError, /divi/)
    end

    it "is safe to share between threads" do
      threads = 8.times.map do |i|
        Thread.new do
          50.times.map do |j|
            invalid = (i + j).odd?
            validator.collect_violations(valid_user(name: invalid ? "" : "alice")).size == (invalid ? 1 : 0)
          end
        end
      end
      expect(threads.flat_map(&:value)).to all(be(true))
    end
  end

  describe "descriptor_pool:" do
    it "validates messages defined in a custom pool" do
      pool = Google::Protobuf::DescriptorPool.new
      fdset_path = File.expand_path("../fixtures/spec_messages.fdset", __dir__)
      fdset = Google::Protobuf::FileDescriptorSet.decode(File.binread(fdset_path))
      fdset.file.each { |file| pool.add_serialized_file(Google::Protobuf::FileDescriptorProto.encode(file)) }
      klass = pool.lookup("protovalidate_spec.Address").msgclass
      violations = described_class.new(descriptor_pool: pool).collect_violations(klass.new(city: ""))
      expect(violations.map(&:rule_id)).to eq(["string.min_len"])
    end
  end
end
