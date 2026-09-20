# frozen_string_literal: true

module Protovalidate
  # A single rule violation, wrapping its `buf.validate.Violation` form.
  class Violation
    # @return [Buf::Validate::Violation] the violation as a buf.validate message
    attr_reader :proto

    # @param proto [Buf::Validate::Violation]
    # @param source [Google::Protobuf::MessageExts, nil] the validated message,
    #   used to resolve {#field_value}
    def initialize(proto, source = nil)
      @proto = proto
      @source = source
    end

    # @return [String] identifier of the violated rule, such as `string.min_len`
    def rule_id
      proto.rule_id
    end

    # @return [String] human-readable description of the violation
    def message
      proto.message
    end

    # @return [Boolean] whether the violation is about a map key rather than its value
    def for_key?
      proto.for_key
    end

    # @return [Buf::Validate::FieldPath, nil] path to the violating field, if any
    def field
      proto.field
    end

    # @return [Buf::Validate::FieldPath, nil] path to the violated rule within
    #   the field's `buf.validate.FieldRules`, if any
    def rule
      proto.rule
    end

    # @return [String] {#field} rendered as `a.b[0].c["key"]`, empty for message-level rules
    def field_path
      path = field
      return "" if path.nil?

      path.elements.map { |element| render_element(element) }.join(".")
    end

    # Walks {#field} through the validated message.
    #
    # @return [Object, nil] the value that violated the rule, the map key when
    #   {#for_key?}, or nil when the message is not known or the path does not resolve
    def field_value
      path = field
      return nil if @source.nil? || path.nil?

      elements = path.elements
      value = @source #: untyped
      elements.each_with_index do |element, index|
        return nil unless value.is_a?(Google::Protobuf::MessageExts)

        descriptor = value.class.descriptor.find do |candidate|
          candidate.is_a?(Google::Protobuf::FieldDescriptor) && candidate.number == element.field_number
        end
        descriptor ||= value.class.descriptor.lookup(element.field_name)
        return nil unless descriptor

        value = value[descriptor.name]
        key = subscript_of(element)
        next if key.equal?(NO_SUBSCRIPT)

        last = index == elements.size - 1
        return key if last && for_key?

        value = value[key]
      end
      value
    end

    # @return [String]
    def to_s
      location = field_path
      location = "#{location}: " unless location.empty?
      "#{location}#{message} [#{rule_id}]"
    end

    # @return [String]
    def inspect
      "#<#{self.class.name} #{self}>"
    end

    NO_SUBSCRIPT = Object.new.freeze
    private_constant :NO_SUBSCRIPT

    private def subscript_of(element)
      case element.subscript
      when :index then element.index
      when :bool_key then element.bool_key
      when :int_key then element.int_key
      when :uint_key then element.uint_key
      when :string_key then element.string_key
      else NO_SUBSCRIPT
      end
    end

    private def render_element(element)
      subscript = subscript_of(element)
      return element.field_name if subscript.equal?(NO_SUBSCRIPT)

      "#{element.field_name}[#{subscript.inspect}]"
    end
  end
end
