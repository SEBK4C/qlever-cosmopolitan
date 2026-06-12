# QLever on Cosmopolitan Libc

This directory contains everything needed to build QLever as an
[Actually Portable Executable](https://justine.lol/ape.html): one binary that
runs on Linux, macOS, Windows, FreeBSD, OpenBSD and NetBSD, on both x86_64
and aarch64.

See `AUDIT.md` for the Phase 0 dependency/platform audit and the list of
toolchain quirks discovered along the way.

## Build pipeline

```sh
# 0. one-time: fetch the toolchain (~1 GB unpacked)
mkdir -p ~/cosmocc && cd ~/cosmocc \
  && curl -LO https://cosmo.zip/pub/cosmocc/cosmocc.zip \
  && unzip cosmocc.zip && chmod +x bin/*

# 1. build third-party deps into the ~/cosmos sysroot (idempotent)
sh cosmo/build-deps.sh

# 2. configure + build QLever (binaries land in build-cosmo/)
sh cosmo/build.sh

# 3. embed the ICU data archive into the APE binaries
sh cosmo/package.sh

# 4. feature-parity gate
#    e2e expected-results suite against the cosmo build:
bash cosmo/parity-check.sh e2e
#    full parity vs a native reference build in build-ref/:
bash cosmo/parity-check.sh -r build-ref e2e refe2e crossdiff
#    unit tests (build them first: TARGETS=all sh cosmo/build.sh):
bash cosmo/parity-check.sh unit
```

Environment knobs: `COSMOCC` (toolchain root), `COSMOS` (sysroot prefix),
`BUILD_DIR`, `TARGETS`, `JOBS`.

## How it works

- `toolchains/cosmocc.cmake` presents cosmocc to CMake as a static-only
  Linux-ish cross toolchain, with `/bin/sh` as the test-binary launcher
  (APE files can't be `execve()`'d directly on all hosts).
- `build-deps.sh` builds zlib/zstd/OpenSSL/ICU/Boost from source with
  cosmocc, pinned to the same versions as `conanfile.txt`. Boost gets the
  errno patches from `patch_boost_cosmo.py` (errno constants are runtime
  symbols under Cosmopolitan — see AUDIT.md), and aarch64 twin archives are
  installed to `lib/.aarch64/`.
- ICU data ships as a standalone `icudt76l.dat`, embedded into the binaries'
  zip section by `package.sh`; `src/util/CosmopolitanIcuInit.h` points ICU
  at `/zip/icu` at startup (no-op for regular builds). Non-packaged dev
  binaries use `ICU_DATA=$HOME/cosmos/share/icu/76.1` instead (the parity
  script sets this automatically).
- jemalloc is intentionally absent (optional upstream); cosmo's malloc is
  used. Revisit for IndexBuilder performance once parity is green.
