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

  describe "#register" do
    it "compiles ahead so the first validation finds the rules ready" do
      engine = validator.instance_variable_get(:@engine)
      allow(engine).to receive(:compile).and_call_original
      validator.register(ProtovalidateSpec::User)
      expect(engine).to have_received(:compile).with("protovalidate_spec.User").once

      expect(validator.collect_violations(valid_user(name: "")).map(&:rule_id)).to eq(["string.min_len"])
      expect(engine).to have_received(:compile).once
    end

    it "raises CompilationError before any message is validated" do
      expect { validator.register(ProtovalidateSpec::BadRule) }
        .to raise_error(Protovalidate::CompilationError, /overload/i)
    end

    it "raises TypeError for something that is not a message class" do
      expect { validator.register(String) }.to raise_error(TypeError, /expected a Google::Protobuf message class/)
    end

    it "accepts several classes and is idempotent" do
      engine = validator.instance_variable_get(:@engine)
      allow(engine).to receive(:compile).and_call_original
      2.times { validator.register(ProtovalidateSpec::User, ProtovalidateSpec::Address) }
      expect(engine).to have_received(:compile).twice
    end
  end

  describe "#register_all" do
    let(:pool) do
      Google::Protobuf::DescriptorPool.new.tap do |pool|
        fdset = Google::Protobuf::FileDescriptorSet.decode(File.binread(File.expand_path("../fixtures/spec_messages.fdset", __dir__)))
        fdset.file.each { |file| pool.add_serialized_file(Google::Protobuf::FileDescriptorProto.encode(file)) }
      end
    end

    it "registers the loaded classes of its own pool and skips other pools" do
      classes = %w[protovalidate_spec.User protovalidate_spec.Address].map { |name| pool.lookup(name).msgclass }
      validator = described_class.new(descriptor_pool: pool)
      engine = validator.instance_variable_get(:@engine)
      allow(engine).to receive(:compile).and_call_original

      validator.register_all

      expect(engine).to have_received(:compile).with("protovalidate_spec.User").once
      expect(engine).to have_received(:compile).with("protovalidate_spec.Address").once
      expect(engine).to have_received(:compile).twice
      expect(validator.collect_violations(classes.fetch(1).new(city: "")).map(&:rule_id)).to eq(["string.min_len"])
    end

    it "skips loaded types the engine does not know instead of raising" do
      unknown = ProtovalidateSpec::User.superclass.subclasses.find do |klass|
        described_class.new.register(klass)
        false
      rescue Protovalidate::CompilationError
        false
      rescue ArgumentError => e
        e.message.include?("unknown message type")
      end
      expect(unknown).not_to be_nil

      allow(validator).to receive(:loaded_message_classes).and_return([unknown, ProtovalidateSpec::User])
      validator.register_all
      expect(validator.collect_violations(valid_user(name: "")).map(&:rule_id)).to eq(["string.min_len"])
      expect { validator.validate(unknown.new) }.to raise_error(ArgumentError, /unknown message type/)
    end

    it "raises CompilationError when a loaded message type has a rule that does not compile" do
      expect(ProtovalidateSpec::BadRule.superclass.subclasses).to include(ProtovalidateSpec::BadRule)
      expect { validator.register_all }.to raise_error(Protovalidate::CompilationError, /overload/i)
    end
  end

  describe "the registered fast path" do
    it "looks up the descriptor only once per message class" do
      allow(ProtovalidateSpec::User).to receive(:descriptor).and_call_original
      3.times { validator.collect_violations(valid_user) }
      expect(ProtovalidateSpec::User).to have_received(:descriptor).once
    end

    it "is safe to share between threads while other types register" do
      validator.register(ProtovalidateSpec::User)
      threads = 8.times.map do |i|
        Thread.new do
          50.times.map do |j|
            invalid = (i + j).odd?
            case j % 3
            when 0
              validator.collect_violations(ProtovalidateSpec::Address.new(city: invalid ? "" : "Tokyo")).size == (invalid ? 1 : 0)
            when 1
              validator.collect_violations(ProtovalidateSpec::RuntimeFailure.new(divisor: 1)).empty?
            else
              validator.collect_violations(valid_user(name: invalid ? "" : "alice")).size == (invalid ? 1 : 0)
            end
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
