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
| `arm-linux-gnu` (ARMv7, hard float) | glibc 2.31 or newer |
| `x86_64-linux-musl`, `aarch64-linux-musl` | musl libc, e.g. Alpine Linux |
| `arm64-darwin` | macOS 11 or newer |
| `x64-mingw-ucrt` | RubyInstaller (UCRT) Ruby |

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

The rules of a message type are compiled the first time a message of that type is validated, and protovalidate-cc holds an exclusive lock while it compiles, so every concurrent validation on the same validator waits until the compilation finishes. To keep that off the request path, register the message types your application validates at boot, for example from a Rails initializer or before the server forks workers:

```ruby
Protovalidate.register(Example::User, Example::Order)
```

`Protovalidate.register_all` registers every message class loaded so far instead of a hand-maintained list, so call it once all generated code has been loaded. In a Rails application, `config.after_initialize` callbacks run in the `finisher_hook` initializer, after the `eager_load!` initializer, so with `config.eager_load` enabled every generated class under an autoload path is already loaded by then. Without eager loading, only the classes loaded so far are registered and the rest compile on first use. Generated code outside the autoload paths, such as under `lib/`, must be required before the callback runs.

```ruby
# config/initializers/protovalidate.rb
Rails.application.config.after_initialize do
  Protovalidate.register_all
end
```

Types that were not registered still compile on first use, so registration is an optimization rather than a requirement. Both methods raise `Protovalidate::CompilationError` for a rule that does not compile, so a bad rule fails at boot rather than on the first request that reaches it. `register_all` skips message types the engine cannot see, which happens when google-protobuf ships a newer copy of a file compiled into the extension, such as `google/protobuf/descriptor.proto`; those types cannot be validated either way. Once a type is registered, validating it takes no lock on the Ruby side, and the shared validator returned by `Protovalidate.validator` is created once and then read without locking.

## Development

```bash
bin/setup                        # submodules, bundle, rbs collection, hk hooks
bundle exec rake compile         # builds the extension (RB_SYS_CARGO_PROFILE=dev for faster iteration)
bundle exec rake spec
bundle exec rake conformance     # needs Go; installs the harness into tmp/bin
bundle exec rake steep yard:check rubocop
```

The native code lives in `ext/protovalidate`: `src/lib.rs` binds `Protovalidate::Native::Engine` with [magnus](https://github.com/matsadler/magnus), and `sys/` compiles protovalidate-cc and its dependencies from git submodules using file lists derived from protovalidate-cc's Bazel build. To move to a new protovalidate-cc release, edit `ext/protovalidate/sys/versions.json`, run `script/extract-native-sources` (needs Bazel), update `PROTOVALIDATE_VERSION` in `lib/protovalidate/version.rb` if the specification version moved, and run `bundle exec rake proto:generate`.

Precompiled gems are assembled by `.github/workflows/native.yml`: glibc Linux builds run inside manylinux_2_34 containers, macOS builds on macos-15 and Windows builds on windows-2025. musl and 32-bit ARM builds are cross-compiled with `rake cross compile` inside [rb-sys-dock](https://github.com/oxidize-rb/rb-sys) images, with newer cross compilers swapped in. `rake 'gem:native[PLATFORM]'` packages one gem per platform.

## License

Apache License 2.0, see LICENSE.txt. Third-party components compiled into the extension are listed in NOTICE.md.
