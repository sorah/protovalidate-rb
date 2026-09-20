# frozen_string_literal: true

module Protovalidate
  # Base class of the errors raised by this gem.
  class Error < StandardError; end

  # Raised when the rules of a message type cannot be compiled, for example a
  # CEL expression that does not parse or type-check.
  class CompilationError < Error; end

  # Raised when a rule fails while being evaluated against a message.
  class EvaluationError < Error; end

  # Raised by {Protovalidate.validate} and {Validator#validate} for a message
  # that violates its rules.
  class ValidationError < Error
    # @return [Array<Violation>] the violations, in evaluation order
    attr_reader :violations

    # @param message [String]
    # @param violations [Array<Violation>]
    def initialize(message, violations)
      super(message)
      @violations = violations
    end

    # @return [Buf::Validate::Violations] the violations as a buf.validate message
    def to_proto
      Buf::Validate::Violations.new(violations: violations.map(&:proto))
    end
  end
end
