# frozen_string_literal: true

RSpec.describe Protovalidate::Violation do
  let(:validator) { Protovalidate::Validator.new }

  def violation_for(message)
    validator.collect_violations(message).fetch(0)
  end

  describe "#field_value" do
    it "resolves a scalar field" do
      expect(violation_for(valid_user(name: "")).field_value).to eq("")
    end

    it "resolves a nested field" do
      message = valid_user(address: ProtovalidateSpec::Address.new(city: ""))
      expect(violation_for(message).field_value).to eq("")
    end

    it "resolves a repeated item" do
      expect(violation_for(valid_user(tags: ["ok", ""])).field_value).to eq("")
    end

    it "resolves a map value" do
      expect(violation_for(valid_user(scores: {"math" => -5})).field_value).to eq(-5)
    end

    it "resolves a map key for key violations" do
      violation = violation_for(valid_user(scores: {"" => 1}))
      expect(violation.for_key?).to be(true)
      expect(violation.field_value).to eq("")
    end

    it "is nil for message-level rules" do
      expect(violation_for(valid_user(name: "admin")).field_value).to be_nil
    end

    it "is nil without the source message" do
      proto = violation_for(valid_user(name: "")).proto
      expect(described_class.new(proto).field_value).to be_nil
    end
  end

  describe "#to_s" do
    it "renders the path, message and rule id" do
      expect(violation_for(valid_user(tags: ["ok", ""])).to_s)
        .to eq("tags[1]: must be at least 1 characters [string.min_len]")
    end

    it "omits the path for message-level rules" do
      expect(violation_for(valid_user(name: "admin")).to_s).to eq("name must not be admin [user.name_not_admin]")
    end
  end

  describe "#inspect" do
    it "wraps to_s" do
      expect(violation_for(valid_user(name: "")).inspect)
        .to eq("#<Protovalidate::Violation name: must be at least 1 characters [string.min_len]>")
    end
  end

  describe "#rule" do
    it "points at the violated rule within FieldRules" do
      rule = violation_for(valid_user(name: "")).rule
      expect(rule.elements.map(&:field_name)).to eq(["string", "min_len"])
    end
  end
end
