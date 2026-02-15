# AGENTS.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Purpose

Custom Homebrew tap containing patched formulae for macOS 10.15 (Catalina) compatibility. Homebrew no longer officially supports Catalina (Tier 3), so formulae here include fixes for build failures on that platform.

## Formula Development

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

## CI/CD

- `tests.yml`: Runs `brew test-bot` on PRs (ubuntu-22.04, macos-15-intel, macos-26)
- `publish.yml`: Merges PRs and publishes bottles when `pr-pull` label is applied

Note: CI tests on modern macOS versions; actual 10.15 testing must be done locally.
