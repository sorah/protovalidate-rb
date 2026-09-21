# protovalidate

Ruby implementation of [protovalidate](https://github.com/bufbuild/protovalidate): validates Protobuf messages against the `buf.validate` rules declared in their schema, with rules written in [CEL](https://cel.dev).

Validation is performed by [protovalidate-cc](https://github.com/bufbuild/protovalidate-cc), compiled into a native extension together with cel-cpp and its dependencies. The gem passes the upstream conformance suite for protovalidate 1.2.2.

## Installation

```bash
bundle add protovalidate
```

Precompiled gems are published for:

| Platform | Requirements |
|---|---|
| `x86_64-linux-gnu`, `aarch64-linux-gnu` | glibc 2.34 or newer |
| `arm64-darwin` | macOS 11 or newer |

Each covers Ruby 3.3, 3.4 and 4.0. On other platforms or Ruby versions the source gem is built at install time, which needs a Rust toolchain (1.85+), a C++17 compiler and a few minutes: it compiles protovalidate-cc, cel-cpp, abseil, protobuf, re2 and the ANTLR runtime.

Messages must come from [google-protobuf](https://rubygems.org/gems/google-protobuf) 4.31 or newer.

## Usage

Annotate your schema with `buf.validate` rules ([reference](https://buf.build/docs/protovalidate/)), generate Ruby code as usual, then:

```ruby
require "protovalidate"

user = Example::User.new(name: "", email: "not an email")

begin
  Protovalidate.validate(user)
rescue Protovalidate::ValidationError => e
  e.violations.each { |violation| puts violation }
  # name: value length must be at least 1 characters [string.min_len]
  # email: value must be a valid email address [string.email]
end

Protovalidate.collect_violations(user) # => [#<Protovalidate::Violation ...>, ...]
Protovalidate.validate(user, fail_fast: true)
```

`Protovalidate.validate` and `Protovalidate.collect_violations` share one process-wide `Protovalidate::Validator`. Build your own when messages come from a `Google::Protobuf::DescriptorPool` other than the generated pool:

```ruby
validator = Protovalidate::Validator.new(descriptor_pool: pool)
validator.collect_violations(message)
```

### Violations

Each `Protovalidate::Violation` exposes the `buf.validate.Violation` message as `#proto`, plus:

- `#rule_id`, `#message`, `#for_key?`
- `#field` and `#rule` (`Buf::Validate::FieldPath`), `#field_path` rendered as `items[2].name`
- `#field_value`, the offending value resolved from the validated message

`Protovalidate::ValidationError#to_proto` returns the `Buf::Validate::Violations` message, for example to return it in an API response. The generated `buf/validate/validate_pb.rb` is bundled at its canonical require path.

### Errors

| Error | Meaning |
|---|---|
| `Protovalidate::ValidationError` | the message is invalid; `#violations` |
| `Protovalidate::CompilationError` | the rules of the message type do not compile (bad CEL) |
| `Protovalidate::EvaluationError` | a rule failed while being evaluated |
| `ArgumentError` | descriptor problems, such as an import missing from the pool |

All inherit from `Protovalidate::Error` except `ArgumentError`.

### Threads

A `Validator` compiles the rules of each message type once and caches them, so reuse one instance. Validating from several threads at once is supported and releases the GVL while protovalidate-cc runs. Ractors are not supported.

## Development

```bash
bin/setup                        # submodules, bundle, rbs collection, hk hooks
bundle exec rake compile         # builds the extension (RB_SYS_CARGO_PROFILE=dev for faster iteration)
bundle exec rake spec
bundle exec rake conformance     # needs Go; installs the harness into tmp/bin
bundle exec rake steep yard:check rubocop
```

The native code lives in `ext/protovalidate`: `src/lib.rs` binds `Protovalidate::Native::Engine` with [magnus](https://github.com/matsadler/magnus), and `sys/` compiles protovalidate-cc and its dependencies from git submodules using file lists derived from protovalidate-cc's Bazel build. To move to a new protovalidate-cc release, edit `ext/protovalidate/sys/versions.json`, run `script/extract-native-sources` (needs Bazel), update `PROTOVALIDATE_VERSION` in `lib/protovalidate/version.rb` if the specification version moved, and run `bundle exec rake proto:generate`.

Precompiled gems are assembled by `.github/workflows/native.yml`: Linux builds run inside manylinux_2_34 containers, macOS builds on macos-15, and `rake 'gem:native[PLATFORM]'` packages one gem per platform.

## License

Apache License 2.0, see LICENSE.txt. Third-party components compiled into the extension are listed in NOTICE.md.
