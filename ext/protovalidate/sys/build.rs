// Copyright (c) 2023-2026 Buf Technologies, Inc.
// Copyright (c) 2026 Sorah Fukumori
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

//! Compiles protovalidate-cc and the C++ libraries it builds on.
//!
//! Upstream sources are git submodules under `third_party/`, pinned to the
//! versions bazel resolves for the protovalidate-cc release named in
//! `versions.json`. Code that has no upstream file to point at, protoc output
//! and the ANTLR-generated CEL parser, is checked in under `gen/`, because
//! regenerating it would need protoc and a JVM at build time. Which files to
//! compile is recorded per library in `filelists/`. All of it is produced by
//! `script/extract-native-sources` from bazel's action graph.

use std::env;
use std::ffi::OsStr;
use std::path::{Path, PathBuf};

/// The directory of this crate.
fn manifest_dir() -> PathBuf {
    PathBuf::from(env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR"))
}

fn rerun_if_changed(path: &Path) {
    println!("cargo::rerun-if-changed={}", path.display());
}

/// Whether the C++ compilation can be skipped for this build. Lint runs
/// (clippy, `PROTOVALIDATE_SKIP_CPP`) do not need the native archives, which
/// also lets a checkout without the `third_party/` submodules lint.
fn should_skip_cpp() -> bool {
    println!("cargo::rerun-if-env-changed=CLIPPY_ARGS");
    println!("cargo::rerun-if-env-changed=PROTOVALIDATE_SKIP_CPP");
    env::var_os("CLIPPY_ARGS").is_some() || env::var_os("PROTOVALIDATE_SKIP_CPP").is_some()
}

/// A submodule checkout under `third_party/`.
fn third_party_dir(name: &str) -> PathBuf {
    let dir = manifest_dir().join("third_party").join(name);
    let mut entries = std::fs::read_dir(&dir)
        .unwrap_or_else(|e| {
            panic!(
                "{}: {e}. Run `git submodule update --init --recursive`.",
                dir.display()
            )
        })
        .map(|entry| entry.expect("read_dir entry").path())
        .filter(|path| path.file_name() != Some(OsStr::new(".git")))
        .peekable();
    assert!(
        entries.peek().is_some(),
        "{} is empty. Run `git submodule update --init --recursive`.",
        dir.display(),
    );
    // Watch the checkout's contents rather than the directory itself. A
    // submodule keeps its own `.git` entry, which git rewrites on any
    // superproject operation, and watching the root would rebuild every C++
    // file each time git touched its bookkeeping.
    for path in entries {
        rerun_if_changed(&path);
    }
    dir
}

/// The checked-in generated sources.
fn gen_dir() -> PathBuf {
    let dir = manifest_dir().join("gen");
    assert!(dir.is_dir(), "{} does not exist", dir.display());
    rerun_if_changed(&dir);
    dir
}

/// Source files a library compiles, as paths relative to the crate root.
///
/// A `windows:`/`linux:`/`macos:` prefix marks a file bazel adds through a
/// platform select(); it is compiled only when the target OS matches.
fn read_filelist(path: &Path) -> Vec<String> {
    let target_os = env::var("CARGO_CFG_TARGET_OS").expect("CARGO_CFG_TARGET_OS");
    rerun_if_changed(path);
    let text = std::fs::read_to_string(path).unwrap_or_else(|e| panic!("{}: {e}", path.display()));
    text.lines()
        .map(str::trim)
        .filter(|line| !line.is_empty() && !line.starts_with('#'))
        .filter_map(|line| match line.split_once(':') {
            Some((os, path)) if ["windows", "linux", "macos"].contains(&os) => {
                (os == target_os).then(|| path.to_owned())
            }
            _ => Some(line.to_owned()),
        })
        .collect()
}

/// Whether the target is Windows with the GNU toolchain (RubyInstaller's).
fn target_is_mingw() -> bool {
    env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows")
        && env::var("CARGO_CFG_TARGET_ENV").as_deref() == Ok("gnu")
}

/// Whether libstdc++ is linked into the extension rather than loaded at
/// runtime. musl distributions do not install libstdc++ by default, and on
/// Windows the MinGW runtime DLLs are not on the PATH Ruby loads from.
fn link_libstdcxx_statically() -> bool {
    env::var("CARGO_CFG_TARGET_ENV").as_deref() == Ok("musl") || target_is_mingw()
}

/// cel-cpp's typeinfo.cc takes `_WIN32` to mean MSVC and demangles with
/// `type_info::raw_name`, which only MSVC has. MinGW gets a copy that tests
/// `_MSC_VER` instead and so takes the Itanium ABI path GCC implements.
fn patch_for_mingw(path: PathBuf) -> PathBuf {
    if !target_is_mingw() || !path.ends_with("third_party/cel-cpp/common/typeinfo.cc") {
        return path;
    }
    let source =
        std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("{}: {e}", path.display()));
    assert_eq!(
        source.matches("#ifdef _WIN32").count(),
        2,
        "{}: the _WIN32 guards moved; revisit patch_for_mingw",
        path.display(),
    );
    let patched =
        PathBuf::from(env::var("OUT_DIR").expect("OUT_DIR")).join("cel_typeinfo_mingw.cc");
    std::fs::write(&patched, source.replace("#ifdef _WIN32", "#ifdef _MSC_VER"))
        .unwrap_or_else(|e| panic!("{}: {e}", patched.display()));
    patched
}

/// One static library built from the C++ sources.
struct CxxLib {
    name: String,
    build: cc::Build,
}

impl CxxLib {
    fn new(name: &str, includes: &[&Path]) -> Self {
        let mut build = cc::Build::new();
        build.cpp(true).warnings(false);

        if build.get_compiler().is_like_msvc() {
            build.std("c++20");
            // msvc does not support cel-cpp's constinit so we clear it
            build.define("constinit", "");
            build.define("_ALLOW_KEYWORD_MACROS", None);
            build.flag("/EHsc").flag("/utf-8").flag("/bigobj");
            build.define("NOMINMAX", None);
            build.define("WIN32_LEAN_AND_MEAN", None);
        } else {
            build.std("c++17");
            build.flag_if_supported("-fsized-deallocation");
            build.flag_if_supported("-faligned-allocation");
            // Everything here is an implementation detail of the extension,
            // which exports only its Init symbol.
            build.flag_if_supported("-fvisibility=hidden");
            build.flag_if_supported("-fvisibility-inlines-hidden");
        }
        if link_libstdcxx_statically() {
            build.cpp_link_stdlib_static(true);
        }
        for dir in includes {
            build.include(dir);
        }

        let root = manifest_dir();
        for file in read_filelist(&root.join(format!("filelists/{name}.txt"))) {
            build.file(patch_for_mingw(root.join(file)));
        }
        Self {
            name: name.to_owned(),
            build,
        }
    }

    /// Adds the defines required to compile against the ANTLR4 C++ runtime
    /// headers, in the runtime itself and its dependents alike.
    fn antlr4_defines(&mut self) -> &mut Self {
        self.build.define("ANTLR4CPP_STATIC", None);
        self.build.define("ANTLR4CPP_USING_ABSEIL", None);
        self
    }

    fn compile(&mut self) {
        self.build.compile(&self.name);
    }
}

fn main() {
    if should_skip_cpp() {
        return;
    }
    let absl = third_party_dir("abseil-cpp");
    let antlr4 = third_party_dir("antlr4").join("runtime/Cpp/runtime/src");
    let re2 = third_party_dir("re2");
    let protobuf_root = third_party_dir("protobuf");
    let celcpp = third_party_dir("cel-cpp");
    let pvcc = third_party_dir("protovalidate-cc");
    let generated = gen_dir();

    let protobuf = protobuf_root.join("src");
    let utf8 = protobuf_root.join("third_party/utf8_range");
    let shim = manifest_dir().join("shim");

    // gen/ is listed after the upstream include roots so that where protobuf
    // ships a checked-in copy of a generated header, the checked-in one wins.
    let mut absl_lib = CxxLib::new("absl", &[&absl]);
    absl_lib.build.define("NOMINMAX", None);

    let mut antlr4_lib = CxxLib::new("antlr4", &[&antlr4, &absl]);
    antlr4_lib.antlr4_defines();

    let mut re2_lib = CxxLib::new("re2", &[&re2, &absl]);

    let mut protobuf_lib = CxxLib::new("protobuf", &[&protobuf, &utf8, &generated, &absl]);

    let mut celcpp_lib = CxxLib::new(
        "celcpp",
        &[&celcpp, &generated, &absl, &protobuf, &utf8, &re2, &antlr4],
    );
    celcpp_lib.antlr4_defines();

    let mut pv_lib = CxxLib::new(
        "protovalidate",
        &[
            &pvcc, &generated, &shim, &celcpp, &absl, &protobuf, &utf8, &re2, &antlr4,
        ],
    );
    pv_lib.antlr4_defines();
    // The C ABI the Rust bindings call through.
    rerun_if_changed(&shim.join("pv_shim.cc"));
    rerun_if_changed(&shim.join("pv_shim.h"));
    pv_lib.build.file(shim.join("pv_shim.cc"));

    // Static archives must precede the archives they reference on the link
    // line, so compile (and therefore emit link directives) most-dependent
    // first.
    pv_lib.compile();
    celcpp_lib.compile();
    protobuf_lib.compile();
    re2_lib.compile();
    antlr4_lib.compile();
    absl_lib.compile();

    // rustc resolves the static libstdc++ itself, so it needs the compiler's
    // library directory.
    if link_libstdcxx_statically() {
        let output = absl_lib
            .build
            .get_compiler()
            .to_command()
            .arg("-print-file-name=libstdc++.a")
            .output()
            .expect("run the C++ compiler");
        let archive = PathBuf::from(String::from_utf8(output.stdout).expect("utf-8").trim());
        let dir = archive.parent().expect("libstdc++.a directory");
        println!("cargo::rustc-link-search=native={}", dir.display());
    }

    // abseil's sysinfo.cc reads the CPU frequency from the registry; bazel
    // links advapi32 through abseil's linkopts.
    if env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
        println!("cargo::rustc-link-lib=advapi32");
    }

    if env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("macos") {
        println!("cargo::rustc-link-lib=framework=CoreFoundation");
    }
}
