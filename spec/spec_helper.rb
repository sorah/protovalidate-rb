# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("gen", __dir__))

require "protovalidate"
require "google/protobuf/well_known_types"
require "protovalidate_spec/messages_pb"

module SpecMessages
  module_function def valid_user(**overrides)
    ProtovalidateSpec::User.new(
      name: "alice",
      email: "alice@example.com",
      age: 30,
      tags: ["ruby", "protobuf"],
      scores: {"math" => 90},
      address: ProtovalidateSpec::Address.new(city: "Tokyo"),
      created_at: Google::Protobuf::Timestamp.from_time(Time.now - 60),
      even: 2,
      **overrides,
    )
  end
end

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
  config.include SpecMessages
end
