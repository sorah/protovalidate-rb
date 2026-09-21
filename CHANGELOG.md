# Changelog

## 0.1.0.beta2 (2026-09-21)

- Precompiled gems for `x86_64-linux-musl`, `aarch64-linux-musl`, `arm-linux-gnu` and `x64-mingw-ucrt`.
- Precompiled Linux glibc gems now require glibc 2.34 or newer (was 2.28); older hosts fall back to the source gem.

## 0.1.0.beta1 (2026-09-20)

- Initial release: `Protovalidate.validate` / `collect_violations` backed by protovalidate-cc 1.2.0 (protovalidate 1.2.2).
