# frozen_string_literal: true

require "set"

module Protovalidate
  # Validates messages against the buf.validate rules of their schema.
  #
  # A validator owns a native engine that compiles the rules of each message
  # type once and caches them, so reuse one instance rather than creating one
  # per validation. Instances may be shared between threads; Ractors are not
  # supported.
  class Validator
    # @param descriptor_pool [Google::Protobuf::DescriptorPool] pool the
    #   validated messages' schema files and their imports are looked up in
    def initialize(descriptor_pool: Google::Protobuf::DescriptorPool.generated_pool)
      @descriptor_pool = descriptor_pool
      @engine = Native::Engine.new
      @registered_files = Set.new
      @registered_types = Set.new
      @registration = Mutex.new
    end

    # Validates a message, raising when it is invalid.
    #
    # @param message [Google::Protobuf::MessageExts]
    # @param fail_fast [Boolean] stop at the first violation
    # @return [void]
    # @raise [ValidationError] when the message violates its rules; its
    #   violations equal what {#collect_violations} returns
    # @raise [CompilationError] when the rules of the message type cannot be compiled
    # @raise [EvaluationError] when a rule fails during evaluation
    # @raise [TypeError] when `message` is not a Protobuf message
    def validate(message, fail_fast: false)
      violations = collect_violations(message, fail_fast:)
      return if violations.empty?

      raise ValidationError.new("invalid #{message.class.descriptor.name}", violations)
    end

    # Validates a message and returns its violations instead of raising.
    #
    # @param message [Google::Protobuf::MessageExts]
    # @param fail_fast [Boolean] stop at the first violation
    # @return [Array<Violation>] empty when the message is valid
    # @raise [CompilationError] when the rules of the message type cannot be compiled
    # @raise [EvaluationError] when a rule fails during evaluation
    # @raise [TypeError] when `message` is not a Protobuf message
    def collect_violations(message, fail_fast: false)
      descriptor = descriptor_of(message)
      register(descriptor)
      serialized = @engine.validate(descriptor.name, message.class.encode(message), fail_fast)
      return [] if serialized.nil?

      Buf::Validate::Violations.decode(serialized).violations.map do |proto|
        Violation.new(proto, message)
      end
    end

    private def descriptor_of(message)
      klass = message.class
      unless klass.respond_to?(:descriptor) && klass.descriptor.is_a?(Google::Protobuf::Descriptor)
        raise TypeError, "expected a Google::Protobuf message, got #{klass}"
      end

      klass.descriptor
    end

    private def register(descriptor)
      return if @registered_types.include?(descriptor.name)

      @registration.synchronize do
        next if @registered_types.include?(descriptor.name)

        register_file(descriptor.file_descriptor)
        @registered_types << descriptor.name
      end
    end

    # The engine resolves imports eagerly, so they are added before the importer.
    private def register_file(file)
      return if @registered_files.include?(file.name)

      proto = file.to_proto
      proto.dependency.each do |name|
        dependency = @descriptor_pool.lookup(name)
        unless dependency.is_a?(Google::Protobuf::FileDescriptor)
          raise ArgumentError, "#{file.name} imports #{name}, which is not in the descriptor pool"
        end

        register_file(dependency)
      end
      @engine.add_file(Google::Protobuf::FileDescriptorProto.encode(proto))
      @registered_files << file.name
    end
  end
end
