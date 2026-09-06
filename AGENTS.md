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

## Git Remote Configuration

This tap's `origin` deliberately splits fetch and push URLs:

```bash
git -C "$(brew --repo wolfman/macos1015-fixes)" remote -v
# origin  https://github.com/OldCrow/homebrew-macos1015-fixes.git (fetch)
# origin  git@github.com:OldCrow/homebrew-macos1015-fixes.git (push)
```

Fetch is HTTPS so `brew update` (which runs `git fetch` in every tap) reads this
public repo anonymously. Push stays on SSH so commits go out over the
yubikey-backed key. This is intentional: an SSH fetch URL makes every
`brew update` trigger a `pinentry-mac` yubikey prompt via gpg-agent's SSH
support. Do not "normalize" the fetch URL back to SSH — the split is the fix,
not an oversight. Restore it with:

```bash
tap=$(brew --repo wolfman/macos1015-fixes)
git -C "$tap" remote set-url origin https://github.com/OldCrow/homebrew-macos1015-fixes.git
git -C "$tap" remote set-url --push origin git@github.com:OldCrow/homebrew-macos1015-fixes.git
```

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
- **`-std=c++20` flag spelling unrecognized**: Apple Clang 12 accepts only the pre-release
  spelling `-std=c++2a`; `-std=c++20` is rejected outright (`invalid value 'c++20'`). Build
  systems that probe for `-std=c++20` and quietly fall back to C++17 then compile the code in
  a standard mode upstream never tests, exposing latent C++17 non-conformance.
  Fix: make the probe ask for `-std=c++2a`, which newer compilers still accept as an alias.
  Note this class of failure is **not** fixed by `ENV.llvm_clang`: the code is genuinely
  ill-formed in C++17, so Homebrew LLVM rejects it too at the same `-std=`. Confirm which it is
  by compiling a reduced case with both compilers at the failing `-std=` before choosing a fix.

## Current Fixes

### boost.rb
- **Problem**: Apple's libc++ on 10.15 lacks `std::aligned_alloc` required by Boost.Asio
- **Fix**: Uses Homebrew LLVM toolchain instead of system clang; links against LLVM's libc++
- **Also fixed**: Setting `CC`/`CXX` to llvm's absolute binary path bypasses Homebrew's superenv
  shim entirely, including its automatic -isystem injection for `/usr/local/include` (clang
  does not search it by default on macOS) and its per-dependency -I/-L injection for `zstd`/`xz`.
  Boost.Build's own internal feature-detection Jamfile checks (which decide whether
  Boost.IOStreams gets zstd/lzma support) run using only the bare `user-config.jam` toolset
  declaration -- they do not see the `cxxflags=`/`linkflags=` properties passed to the final
  `b2 install` command. Without any `<compileflags>`/`<linkflags>` on the toolset declaration,
  those checks silently failed to find `<zstd.h>`/`<lzma.h>` and `libzstd`/`liblzma`, so `b2`
  quietly built Boost.IOStreams without zstd/lzma support with no build error at all --
  surfacing only later as an undefined-symbol *link* error in any code calling
  `zstd_compressor()`/`zstd_decompressor()` (or the lzma equivalents). This was a pre-existing
  gap in this tap's own `boost.rb`, unrelated to the llvm 22->23 upgrade or Apple Clang --
  it would have failed identically on any platform building this exact formula from source.
  Fixed by embedding zstd's and xz's include/lib paths directly into the `using darwin/gcc : :
  ... : <compileflags>... <linkflags>... ;` toolset declaration, so every compile Boost.Build
  performs (including its own internal checks) can find them. Confirmed via `nm` on the built
  `libboost_iostreams.dylib` (zstd symbols present) and `brew test`.
- **Key dependency**: `llvm`, `zstd`, `xz`

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

### libheif.rb
- **Problem**: `libheif/box.cc` uses `std::ranges::all_of`/`std::ranges::find`, which need the
  libc++ `<ranges>` header from macOS 11+. Apple Clang 12 on 10.15 lacks it.
- **Fix**: `inreplace` rewrites the `std::ranges` calls to their C++17 iterator-pair equivalents
  (`std::all_of`/`std::find`); `<algorithm>` is already included, so no compiler change is needed.
- **Key dependency**: none (source-only patch)

### osx-cpu-temp.rb
- **Problem**: The available Catalina bottle's tab has `built_on: null` (a pre-2.5 Homebrew
  artifact); modern Homebrew crashes in `Utils::Bottles.load_tab` dereferencing `tab.built_on["os"]`
  without a nil guard.
- **Fix**: `pour_bottle? { false }` forces a source build, avoiding the broken bottle tab.
- **Key dependency**: none (source build)

### z3.rb
- **Problem**: z3 4.16.0 uses `std::format` (needs libc++ `<format>` from macOS 14+) and C++20
  parenthesized aggregate initialization (P0960); both are absent on Apple Clang 12 / 10.15.
  `llvm` cannot be a build dep here because `llvm` itself depends on `z3`.
- **Fix**: Inject a minimal `std::format` polyfill header (positional `{}` only, via
  `ostringstream`) on the include path, and `inreplace` the paren aggregate init
  (`key_data(...)`/`key_value(...)`) to C++17 brace init.
- **Key dependency**: none (source-only patch + polyfill header)

### tesseract.rb
- **Problem**: Six hard errors in `src/ccstruct/points.h` — `constexpr function never produces a
  constant expression [-Winvalid-constexpr]` for the free `FCOORD` operators (`!`, unary `-`,
  `+`, binary `-`, and both `*`). They default-construct an `FCOORD`, whose `= default`
  constructor leaves both `float` members uninitialized, then assign to them. That body is a
  valid constexpr function only from C++20 (P1331R2, trivial default initialization in constexpr
  contexts); under C++17 Clang rejects it, and `-Winvalid-constexpr` is an error by default.
  Not an Apple Clang bug — Homebrew LLVM 22 rejects the same code at `-std=c++17`, so
  `ENV.llvm_clang` does not help. Other platforms escape it because `configure.ac` probes
  `-std=c++17` then `-std=c++20` and lands on C++20; Apple Clang 12 rejects the `c++20` spelling
  (it accepts only `-std=c++2a`), so configure silently falls back to C++17.
- **Fix**: `inreplace` `configure.ac` before `autogen.sh` so the second probe asks for
  `-std=c++2a`, putting the build in C++20 mode like every other platform.
- **Key dependency**: none (build-configuration patch)
- **Note**: This is a latent upstream bug in tesseract's C++17 fallback path, not a
  macOS-specific quirk; it would fail on any platform whose compiler lacks the `c++20` spelling.

### llvm.rb
- **Problem**: Upgrading llvm 22.1.8 -> 23.1.0 fails under Apple Clang 12.x: `llvm/include/llvm/ADT/bit.h:92:3: error: non-void function 'bit_cast' should return a value [-Wreturn-type]`, first breaking `lib/Support/{ABIBreak,AMDGPUMetadata,APFixedPoint,APFloat}.cpp.o`. Root cause is an Apple Clang 12 bug that only manifests when *consuming* (not building) a precompiled header containing `llvm::bit_cast<>()`, an `inline` function template with SFINAE constraints expressed as defaulted `std::enable_if_t<>` type parameters. Confirmed via isolated repro: emitting the PCH succeeds, but a second translation unit consuming it and instantiating a caller (e.g. `APInt::bitsToDouble()`) reproduces the exact failure. This is a host-compiler bug, not a source defect or SDK-availability issue.
- **Fix**: Build with `llvm@22` as the host compiler (`ENV.llvm_clang` + `depends_on "llvm@22" => :build`, on_macos only); llvm@22's own clang does not reproduce the bug against the same isolated repro. No source patch needed.
- **Also fixed**: upstream's `test do` block unconditionally runs a Z3-backed static analyzer assertion (`-analyzer-constraints=unsupported-z3`) even when `install` disabled Z3 (`LLVM_ENABLE_Z3_SOLVER=OFF`, which happens on any macOS older than Sonoma, since Z3 needs `std::format` from Xcode 15.3+). This is an upstream test-suite oversight, not Catalina-specific -- it would fail `brew test` for any pre-Sonoma `--build-from-source` install. Guarded with `if deps.map(&:name).include?("z3")`, mirroring the same check `install` uses to set `enable_z3`.
- **Key dependency**: `llvm@22` (build, macOS only)
- **Note**: `bit_cast` is header-only `inline` and never exported from `libLLVM.dylib`, so this does not introduce cross-compiler ABI exposure for LLVM's own build (which is fully self-consistent under a single host compiler). The one real consumer that links directly against LLVM/Clang's C++ API, `include-what-you-use`, is handled separately below.

### include-what-you-use.rb
- **Problem**: IWYU links directly against Clang's internal (non-stable) Tooling/AST C++ API and has a strict 1:1 version mapping to a Clang major (see upstream README's "Clang compatibility" table). IWYU 0.26 (the current latest release) targets Clang 22 only; there is no `clang_23` branch or tagged release upstream, only `master` (tracks Clang mainline, not a fixed 23.1.0-compatible point). Depending on plain `"llvm"` here would silently follow this tap's llvm.rb bump to 23 and likely fail to build, or build against a mismatched internal API and misbehave at runtime.
- **Fix**: Depend on `"llvm@22"` explicitly instead of plain `"llvm"`, decoupling IWYU from whatever `"llvm"` resolves to. No version bump: 0.26 is already the latest upstream release.
- **Also fixed**: upstream's `test do` block invokes `include-what-you-use` directly on a C++ file with no `-isystem` flag, relying on default-sysroot header-search auto-detection. IWYU's own binary is a bare ClangTool (not the full `clang`/`clang++` driver), so it does not perform the driver's usual automatic libc++-relative-to-compiler detection; on this machine's CLT/SDK setup this fails with `fatal error: 'iostream' file not found`. Confirmed independent of the llvm@22 pin (same failure mode regardless of LLVM major). Fixed by passing `-isystem #{llvm.opt_include}/c++/v1` explicitly in the test.
- **Key dependency**: `llvm@22`
- **Note**: This is **not** a macOS-specific issue -- it would affect any OS updating to llvm 23 before IWYU ships clang_23 support upstream. Per this document's Upstream Issue Reporting policy, flag this to the user and ask before filing an issue/PR against homebrew-core or IWYU upstream.

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

- `tests.yml`: runs `brew test-bot --only-tap-syntax` on a single `ubuntu-24.04` runner.
- `publish.yml`: merges PRs and publishes bottles when the `pr-pull` label is applied. Dormant --
  nothing produces bottles now that `--only-formulae` is gone; keep it only if that changes.
- Linux runner is pinned to `ubuntu-24.04`, not `ubuntu-22.04`: the latter's glibc 2.35 is older
  than current Homebrew expects, and `brew doctor` (run by `test-bot --only-setup`) treats that
  version mismatch as a hard failure. `ubuntu-24.04` ships glibc 2.39, matching what Homebrew
  auto-installs anyway, avoiding the false failure. `ubuntu-22.04` also begins deprecation on
  2026-09-17.

### Why one Linux runner and no macOS matrix (audited 2026-09-06)

CI cannot build what this tap fixes: GitHub removed the macOS 13 runners on 2025-12-08 and has
never offered 10.15, so no hosted runner runs Catalina or Apple Clang 12. Everything CI *can*
check -- `brew style`, `brew readall --os=all --arch=all`, `brew audit` -- is platform-independent
Ruby linting that returns the same result on every runner, so a macOS matrix re-derived an
identical answer at 10x the per-minute cost.

It also imported unrelated breakage. On 2026-09-02 homebrew-core dropped gmp's Intel macOS
bottles (`arm64_*` and Linux only). `brew style` installs `shellcheck`, which needs `gmp`, so on
`macos-15-intel` it began source-building gmp and hung ~29 minutes on unreachable `gmplib.org`
and `ftpmirror.gnu.org` before failing. Every push after that date failed on that leg alone.

`--only-formulae` and the bottle-artifact upload were dropped with the matrix: both were gated on
`pull_request`, this repo pushes straight to main, and a build on Sequoia/Tahoe would exercise the
wrong compiler regardless.

Real build validation is local, on the target machine -- see Build Commands above.
