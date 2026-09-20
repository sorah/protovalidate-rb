# Notices

protovalidate (the `protovalidate` Ruby gem) is licensed under the Apache
License, Version 2.0 (see LICENSE.txt). It bundles, compiles, or derives from
the following third-party software.

## Bundled and compiled into the native extension

| Project | License | Source |
|---|---|---|
| protovalidate-cc | Apache-2.0 | https://github.com/bufbuild/protovalidate-cc |
| protovalidate (buf.validate protos) | Apache-2.0 | https://github.com/bufbuild/protovalidate |
| CEL C++ (cel-cpp) and cel-spec | Apache-2.0 | https://github.com/cel-expr/cel-cpp |
| Abseil C++ | Apache-2.0 | https://github.com/abseil/abseil-cpp |
| Protocol Buffers (C++ runtime, utf8_range) | BSD-3-Clause | https://github.com/protocolbuffers/protobuf |
| RE2 | BSD-3-Clause | https://github.com/google/re2 |
| ANTLR 4 C++ runtime | BSD-3-Clause | https://github.com/antlr/antlr4 |
| googleapis (rpc/expr protos) | Apache-2.0 | https://github.com/googleapis/googleapis |

The license text of each project is shipped alongside its sources under
`ext/protovalidate/sys/third_party/*/LICENSE*` in the source gem, and in
`licenses/` of precompiled gems.

## Derived from protovalidate-py

`ext/protovalidate/sys/shim/pv_shim.{h,cc}`, `ext/protovalidate/sys/src/lib.rs`,
`ext/protovalidate/sys/build.rs` and `script/extract-native-sources` are adapted
from protovalidate-py (https://github.com/bufbuild/protovalidate-py),
Copyright 2023-2026 Buf Technologies, Inc., licensed under the Apache License,
Version 2.0.
