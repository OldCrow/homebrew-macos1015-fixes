# AGENTS.md

This file provides project-scoped guidance to AI agents and contributors working in this repository.

## Project Overview

`wolfman/macos1015-fixes` is a Homebrew tap of formula overrides targeting macOS 10.15 (Catalina),
Apple Clang 12 (clang-1200), on an Intel Homebrew prefix (`/usr/local`). Homebrew no longer
officially supports Catalina (Tier 3), so formulae here patch build failures on that platform.

All formulas here shadow homebrew-core formulas that fail to build or run on this platform.
They are temporary: remove each one once homebrew-core ships a Catalina bottle or upstream
fixes the issue. Some overrides fix genuine upstream version-compatibility bugs (not
macOS-specific) that happen to block a build on this platform; note this explicitly in the
formula's header comment when it applies (see Formula Conventions below).

## Session Start

Before patching or reinstalling a formula, confirm the local tap is in sync with remote:

```bash
cd $(brew --repo wolfman/macos1015-fixes)
git fetch && git status
```

If local and remote have diverged, reconcile before making further changes.

## Build Commands

```bash
# Compare tap formulae versions against homebrew-core; exit 1 if any are outdated
./scripts/check-upstream

# Audit a formula for style/policy issues before committing
brew audit --strict wolfman/macos1015-fixes/<formula>

# Verify Ruby syntax quickly without invoking a full build
ruby -c Formula/<formula>.rb

# Test a patched formula directly (bypasses the confirmation prompts of `brew install`)
brew install --build-from-source wolfman/macos1015-fixes/<formula>

# Run formula tests
brew test wolfman/macos1015-fixes/<formula>

# Full test-bot validation (as CI runs)
brew test-bot --only-tap-syntax
brew test-bot --only-formulae
```

Dependents that reference an overridden formula by plain name (e.g. `pmd` depending on
`openjdk`) do not automatically pick up the tap version. Install the tap-qualified formula
explicitly first so a keg with that name already exists; Homebrew's dependency resolver then
reuses the installed keg instead of rebuilding from homebrew-core.

### Creating/Updating Formulae

Formulae are based on upstream homebrew-core but modified for 10.15 compatibility. When updating:

1. Compare against current upstream: `/usr/local/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/`
2. Preserve the macOS 10.15-specific modifications
3. Update version, sha256, and any new upstream changes

## Upstream Issue Reporting

Most formulas in this tap exist purely because of macOS 10.15 / Apple Clang 12 incompatibilities.
Some do not: the root cause is a genuine upstream bug or version-compatibility break that would
fail on any OS building from source (e.g. a dependency bump that breaks a consumer's API
assumptions, not a macOS-specific compiler quirk). When diagnosing a build failure turns out to
be one of these broader cases, tell the User before committing the formula and ask whether they
want to draft an issue for the relevant project's upstream tracker or Homebrew's discussion
forums. Do not draft or file the issue unprompted.

## Formula Conventions

- Begin each file with a comment block: problem description, root cause, fix applied,
  and a "Remove this formula once..." line (see `doxygen.rb`, `fastfetch.rb`). Retrofit this
  header onto older formulas opportunistically when they are next touched.
- Use `patch :DATA` + `__END__` for inline patches (preferred over external `.patch` files;
  see `doxygen.rb`).
- Skip `make check`/`ctest` only when test failures are demonstrably platform-specific (SIP
  sandbox, dylib mismatch, ABI mangling mismatch between compilers, etc.). Document the reason
  in the install block comment (see `openjdk@21.rb`, `protobuf@33.rb`).
- When the fix is "build with a newer compiler" rather than a source patch, prefer the LLVM
  Build Pattern below over hand-patching actively-maintained upstream macros/headers, since
  patches to fast-moving code create ongoing merge conflicts.

## Known Apple Clang 12 Failure Patterns

- **Missing `__VA_OPT__` support in C mode**: Apple Clang 12 does not implement the C23
  `__VA_OPT__` preprocessor feature under any `-std=` flag (confirmed absent under `gnu17`,
  `c2x`, and `gnu2x` alike), so macros using it in plain C translation units fail with
  "error: expected expression" at the macro invocation site.
  Fix: build with Homebrew LLVM (`ENV.llvm_clang`).
- **C++20 structured binding capture in a lambda**: capturing a structured binding by value in
  a lambda requires C++20 (P1091R3); some build systems select C++17 for `AppleClang < 17`,
  so `-Wpedantic` promotes the resulting `-Wc++20-extension` warning to a hard error.
  Fix: copy the structured binding to a plain named variable before the lambda.
- **`[[gnu::warn_unused]]` class-attribute misparse**: Apple Clang 12 misparses this attribute
  combined with `__attribute__((visibility(...)))` on a class declaration, treating the class
  as anonymous and cascading into unrelated build failures.
  Fix: build with Homebrew LLVM (`ENV.llvm_clang`).
- **NTTP name-mangling mismatch**: Apple Clang 12 and LLVM 22 encode `enable_if` non-type
  template parameters differently (`Li0E` vs. `Tn`-encoded form). Linking an LLVM-compiled
  library (e.g. abseil) against an Apple-Clang-compiled consumer produces missing symbols.
  Fix: build the whole dependency chain with the same compiler (Homebrew LLVM).
- **Missing macOS 11+ SDK symbols behind a runtime-only guard**: code guarded by
  `@available(macOS 11, *)` is still compiled unconditionally, so SDK-11-only symbols
  (e.g. `NSBundleExecutableArchitectureARM64`) referenced inside the guarded block fail to
  compile against the 10.15 SDK even though they're never reached at runtime.
  Fix: add a compile-time `#ifndef`/`#define` guard before first use.
- **Missing libc++ functions**: Apple's libc++ on 10.15 lacks functions newer code assumes are
  present (e.g. `std::aligned_alloc`, required by Boost.Asio).
  Fix: build with Homebrew LLVM toolchain and link against LLVM's libc++.
- **Outdated system libraries silently dropped**: upstream formulas sometimes drop an explicit
  dependency (e.g. `libiconv`) assuming the OS-provided version is new enough; on 10.15 it isn't.
  Fix: re-add the dependency explicitly and point the relevant env var (e.g. `ICONVDIR`) at it.

## Current Fixes

### boost.rb
- **Problem**: Apple's libc++ on 10.15 lacks `std::aligned_alloc` required by Boost.Asio
- **Fix**: Uses Homebrew LLVM toolchain instead of system clang; links against LLVM's libc++
- **Key dependency**: `llvm`

### gettext.rb
- **Problem**: Configure auto-detects json-c but generates malformed include path
- **Fix**: Explicitly adds json-c to dependencies with proper CPPFLAGS/LDFLAGS
- **Key dependency**: `json-c`

### source-highlight.rb
- **Problem**: Links against both boost (LLVM libc++) and system libc++, causing ABI mismatch
- **Fix**: Build with LLVM toolchain to match boost's libc++ linkage
- **Key dependency**: `llvm`

### protobuf.rb
- **Problem**: `PROTOBUF_FUTURE_ADD_EARLY_WARN_UNUSED` expands via `ABSL_ATTRIBUTE_WARN_UNUSED` to `[[gnu::warn_unused]]`; Apple Clang 12.x misparses this combined with `__attribute__((visibility(...)))` on class declarations, treating `GzipInputStream`/`GzipOutputStream` as anonymous and cascading to 20 build failures in `gzip_stream.cc`
- **Fix**: Build with Homebrew LLVM (`ENV.llvm_clang`); tests enabled (googletest build dep, ctest step)
- **Key dependency**: `llvm` (build), `googletest` (build)

### protobuf@33.rb
- **Problem**: Same `[[gnu::warn_unused]]` Apple Clang 12.x parse failure as protobuf.rb
- **Fix**: Build with Homebrew LLVM (`ENV.llvm_clang`); tests disabled (Apple Clang/LLVM mangling mismatch for `enable_if` NTTPs means `absl::Cord::Cord<string,0>` symbol cannot be resolved regardless of compiler used for tests)
- **Key dependency**: `llvm` (build)

### abseil.rb
- **Problem**: Apple Clang 12.x lacks support for `[[gnu::warn_unused]]` as a class attribute; also encodes `enable_if` non-type template parameters (NTTPs) with different C++ name mangling than LLVM 22 (`Li0E` vs `Tn`-encoded form), causing missing symbols when LLVM-compiled consumers link against Apple-Clang-compiled abseil
- **Fix**: Build with Homebrew LLVM (`ENV.llvm_clang`) so `extern template` instantiations like `Cord::Cord<string,0>` export with LLVM's NTTP mangling, matching all LLVM-compiled consumers
- **Key dependency**: `llvm` (build)

### git.rb
- **Problem**: (1) git 2.53.0 had a broken `contrib/credential/osxkeychain/Makefile` that referenced the top-level Makefile incorrectly (fixed in 2.54.0 upstream). (2) Upstream removed `libiconv` from the macOS dependency list (homebrew-core/pull/258461); on macOS 10.15 the system `libiconv` is too old, so the Homebrew dep and `ICONVDIR` must be set explicitly. (3) `contrib/credential/netrc`'s test harness sources `t/test-lib.sh`, which requires sandbox infrastructure unavailable in the Homebrew build environment on macOS 10.15.
- **Fix**: Version pinned to 2.54.0 (osxkeychain issue resolved upstream). `libiconv` kept as an `on_macos` dep alongside `gettext`; `ENV["ICONVDIR"]` set in install. `make build` used instead of `make test` for the netrc helper.
- **Key dependency**: `libiconv` (runtime, macOS only)

### grpc.rb
- **Problem**: Links against abseil; Apple Clang 12.x produces different NTTP mangling for `absl::Cord::Cord<string,0>` than our LLVM-compiled abseil exports, causing undefined symbol at link time. Also, `grpc_cli` sub-build fails because Google Benchmark's regex detection doesn't work under LLVM on macOS 10.15
- **Fix**: Build with Homebrew LLVM (`ENV.llvm_clang`); `grpc_cli` dropped (upstream removes it at 1.80.0)
- **Key dependency**: `llvm` (build)

### doxygen.rb
- **Problem**: `dotrunner.cpp` captures the structured binding variable `dirStr` inside a lambda (`auto process = [this,cmd,dirStr]() -> size_t`). Capturing structured bindings in lambdas requires C++20 (P1091R3). Doxygen's `CMakeLists.txt` selects C++17 for AppleClang < 17, so the build fails under Apple Clang 12.x with `-Wpedantic` promoting `-Wc++20-extension` to an error.
- **Fix**: `inreplace` copies `dirStr` to a plain named variable (`dirStrCopy`) before the lambda and renames the reference inside the lambda body. No compiler change required.
- **Key dependency**: none (source-only patch)

### re2.rb
- **Problem**: No build failure, but re2 links against abseil and should use the same compiler for full ABI consistency across the abseil dependency chain
- **Fix**: Build with Homebrew LLVM (`ENV.llvm_clang`)
- **Key dependency**: `llvm` (build)

### openjdk@21.rb
- **Problem**: Two build failures under the 10.15 SDK:
  1. `CGraphicsDevice.m` uses `NSBundleExecutableArchitectureARM64`, added in the macOS 11.0 SDK for Apple Silicon. The 10.15 SDK does not define it, producing a hard compile error even though the usage is guarded by `@available(macOS 11, *)` (a runtime guard, not a compile-time one).
  2. The boot JDK's `libawt.dylib` hard-links against `JavaRuntimeSupport.framework`. On this machine the framework is nested inside `JavaVM.framework` rather than at the top-level path dyld expects, causing `DTDBuilder` (a Java build tool that loads AWT) to fail with `UnsatisfiedLinkError`.
- **Fix**: Source-only patch adding `#ifndef NSBundleExecutableArchitectureARM64` / `#define` / `#endif` before the first use in `CGraphicsDevice.m`. `DYLD_FRAMEWORK_PATH` is extended in `install` to include `JavaVM.framework/Versions/A/Frameworks` so dyld resolves the framework at its actual location.
- **Key dependency**: none (source-only patch + env var)
- **Note**: JDK 25 (`openjdk.rb`) was attempted first but abandoned — it had three separate 10.15 issues (`VM_MEMORY_MALLOC_PROB_GUARD`, `-Wl,-reproducible`, plus the same DTDBuilder/`JavaRuntimeSupport` path issue). JDK 21 needed only the two fixes above.

### pmd.rb
- **Problem**: The upstream `pmd.rb` formula depends on `openjdk` (currently JDK 25), which cannot be built on macOS 10.15. PMD 7.x requires only Java 8+.
- **Fix**: Depend on `wolfman/macos1015-fixes/openjdk@21` instead. No other changes from upstream.
- **Key dependency**: `wolfman/macos1015-fixes/openjdk@21`

### fastfetch.rb
- **Problem**: `src/common/library.h`'s `FF_LIBRARY_LOAD` macro uses `__VA_OPT__`, a C23
  preprocessor feature. Apple Clang 12 doesn't implement it in C mode under any `-std=` flag,
  so `src/common/impl/lua.c` and `src/common/impl/networking_common.c` fail with
  "error: expected expression" at the macro invocation site.
- **Fix**: Build with Homebrew LLVM (`ENV.llvm_clang`), which supports `__VA_OPT__`, instead of
  patching the actively-changing macro.
- **Key dependency**: `llvm` (build)

## LLVM Build Pattern

The standard fix for Apple Clang 12.x incompatibilities is to build with Homebrew LLVM:

```ruby
on_macos do
  depends_on "llvm" => :build
end

def install
  ENV.llvm_clang if OS.mac?
  # ...
end
```

`ENV.llvm_clang` is Homebrew's built-in method — it sets `CC`/`CXX` to the `llvm` formula's clang within the sandboxed build environment. This is the **only reliable way** to use LLVM for Homebrew builds; Homebrew ignores user-level `CC`/`CXX`/`LDFLAGS` exports from the shell environment.

### Legacy: `brew-llvm` alias

The shell has a `brew-llvm` alias and `~/.homebrew-llvm-wrappers/` that prepend LLVM to PATH before invoking brew. This predates the tap formula approach and is **unreliable** — Homebrew's superenv shim layer intercepts compiler calls regardless of PATH. Do not use it for new formulas. If a formula needs LLVM, add it to this tap with `ENV.llvm_clang`. The alias can serve as a last-resort fallback for one-off installs from homebrew-core where adding a tap formula is not warranted.

## CI/CD

- `tests.yml`: Runs `brew test-bot` on PRs (ubuntu-24.04, macos-15-intel, macos-26), `fail-fast: false`
  so all matrix legs run to completion independently.
- `publish.yml`: Merges PRs and publishes bottles when `pr-pull` label is applied
- Linux runner is pinned to `ubuntu-24.04`, not `ubuntu-22.04`: the latter's glibc 2.35 is older
  than current Homebrew expects, and `brew doctor` (run by `test-bot --only-setup`) treats that
  version mismatch as a hard failure. `ubuntu-24.04` ships glibc 2.39, matching what Homebrew
  auto-installs anyway, avoiding the false failure.

Note: CI tests on modern macOS versions; actual 10.15 testing must be done locally.
