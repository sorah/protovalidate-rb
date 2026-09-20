# frozen_string_literal: true

RSpec.describe Protovalidate do
  it "has a version number" do
    expect(Protovalidate::VERSION).to match(/\A\d+\.\d+\.\d+/)
  end

  it "records the protovalidate specification version" do
    expect(Protovalidate::PROTOVALIDATE_VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end

  describe ".validator" do
    it "returns the same validator every time" do
      expect(Protovalidate.validator).to be_a(Protovalidate::Validator)
      expect(Protovalidate.validator).to equal(Protovalidate.validator)
    end
  end

  describe ".validate" do
    it "returns nil for a valid message" do
      expect(Protovalidate.validate(valid_user)).to be_nil
    end

    it "raises ValidationError for an invalid message" do
      expect { Protovalidate.validate(valid_user(name: "")) }.to raise_error(Protovalidate::ValidationError) do |error|
        expect(error.message).to eq("invalid protovalidate_spec.User")
        expect(error.violations.map(&:rule_id)).to eq(["string.min_len"])
        expect(error.to_proto).to be_a(Buf::Validate::Violations)
        expect(error.to_proto.violations.size).to eq(1)
      end
    end

    it "passes fail_fast through" do
      message = valid_user(name: "", age: -1)
      expect { Protovalidate.validate(message, fail_fast: true) }.to raise_error(Protovalidate::ValidationError) do |error|
        expect(error.violations.size).to eq(1)
      end
    end
  end

  describe ".collect_violations" do
    it "returns an empty array for a valid message" do
      expect(Protovalidate.collect_violations(valid_user)).to eq([])
    end

    it "returns every violation of an invalid message" do
      violations = Protovalidate.collect_violations(valid_user(name: "", age: -1))
      expect(violations.map(&:rule_id)).to contain_exactly("string.min_len", "int32.gte_lte")
    end
  end
end
