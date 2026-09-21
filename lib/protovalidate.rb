# frozen_string_literal: true

require "google/protobuf"
require "google/protobuf/descriptor_pb"

require_relative "protovalidate/version"
require_relative "protovalidate/errors"

# Validates Protobuf messages against the buf.validate rules declared in their
# schema. Rules are evaluated by protovalidate-cc through a native extension.
#
# @example
#   Protovalidate.validate(message)                # raises Protovalidate::ValidationError
#   Protovalidate.collect_violations(message).each { |v| puts v }
module Protovalidate
  DEFAULT_VALIDATOR_LOCK = Mutex.new
  private_constant :DEFAULT_VALIDATOR_LOCK

  # The validator shared by {validate} and {collect_violations}, built on first use.
  #
  # @return [Validator]
  def self.validator
    @validator || DEFAULT_VALIDATOR_LOCK.synchronize { @validator ||= Validator.new }
  end

  # Validates a message with the shared validator.
  #
  # @param (see Validator#validate)
  # @return [void]
  # @raise (see Validator#validate)
  def self.validate(message, fail_fast: false)
    validator.validate(message, fail_fast:)
  end

  # Compiles the rules of message classes ahead of their first validation with
  # the shared validator, for example at application boot.
  #
  # @param (see Validator#register)
  # @return [void]
  # @raise (see Validator#register)
  def self.register(*message_classes)
    validator.register(*message_classes)
  end

  # Collects the violations of a message with the shared validator.
  #
  # @param (see Validator#collect_violations)
  # @return (see Validator#collect_violations)
  # @raise (see Validator#collect_violations)
  def self.collect_violations(message, fail_fast: false)
    validator.collect_violations(message, fail_fast:)
  end
end

require_relative "protovalidate/native"
require_relative "buf/validate/validate_pb"
require_relative "protovalidate/violation"
require_relative "protovalidate/validator"
