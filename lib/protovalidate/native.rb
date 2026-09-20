# frozen_string_literal: true

# Precompiled gems carry one extension per Ruby minor under lib/protovalidate/<X.Y>/.
fat = File.expand_path("#{RUBY_VERSION[/\A\d+\.\d+/]}/protovalidate_native", __dir__.to_s)
if File.exist?("#{fat}.#{RbConfig::CONFIG.fetch("DLEXT")}")
  require fat
else
  require_relative "protovalidate_native"
end

# @!parse
#   module Protovalidate
#     # Binding to protovalidate-cc, implemented by the native extension.
#     # @api private
#     module Native
#       # A descriptor pool plus a rule cache. Bytes in, bytes out.
#       # @api private
#       class Engine
#         # @param file [String] a serialized google.protobuf.FileDescriptorProto
#         # @return [void]
#         def add_file(file); end
#
#         # @param type_name [String] fully qualified message name
#         # @param payload [String] the serialized message
#         # @param fail_fast [Boolean]
#         # @return [String, nil] serialized buf.validate.Violations, or nil when valid
#         def validate(type_name, payload, fail_fast); end
#       end
#     end
#   end
