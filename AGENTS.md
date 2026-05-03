# AGENTS.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Purpose

Custom Homebrew tap containing patched formulae for macOS 10.15 (Catalina) compatibility. Homebrew no longer officially supports Catalina (Tier 3), so formulae here include fixes for build failures on that platform.

## Formula Development

### Checking for Upstream Updates

```bash
./scripts/check-upstream
```

Compares tap formulae versions against homebrew-core. Returns exit code 1 if any are outdated.

### Testing Formulae Locally

```bash
# Audit formula syntax
brew audit --strict Formula/<name>.rb

# Test installation from source
brew install --build-from-source wolfman/macos1015-fixes/<name>

# Run formula tests
brew test wolfman/macos1015-fixes/<name>

# Full test-bot validation (as CI runs)
brew test-bot --only-tap-syntax
brew test-bot --only-formulae
```

### Creating/Updating Formulae

Formulae are based on upstream homebrew-core but modified for 10.15 compatibility. When updating:

1. Compare against current upstream: `/usr/local/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/`
2. Preserve the macOS 10.15-specific modifications
3. Update version, sha256, and any new upstream changes

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

- `tests.yml`: Runs `brew test-bot` on PRs (ubuntu-22.04, macos-15-intel, macos-26)
- `publish.yml`: Merges PRs and publishes bottles when `pr-pull` label is applied

Note: CI tests on modern macOS versions; actual 10.15 testing must be done locally.
