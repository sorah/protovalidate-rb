# Changelog

## Unreleased

- `Protovalidate.register` and `Validator#register` compile the rules of message types ahead of their first validation, so the compilation, which blocks concurrent validations, can run at boot instead of inside a request. `register_all` does the same for every loaded message class.
- Validating an already seen message type no longer takes a lock or allocates its type name on the Ruby side.

## 0.1.0.beta2 (2026-09-21)

- Precompiled gems for `x86_64-linux-musl`, `aarch64-linux-musl`, `arm-linux-gnu` and `x64-mingw-ucrt`.
- Precompiled Linux glibc gems now require glibc 2.34 or newer (was 2.28); older hosts fall back to the source gem.

## 0.1.0.beta1 (2026-09-20)

- Initial release: `Protovalidate.validate` / `collect_violations` backed by protovalidate-cc 1.2.0 (protovalidate 1.2.2).
