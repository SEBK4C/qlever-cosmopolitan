# QLever on Cosmopolitan Libc

This directory contains everything needed to build QLever as an
[Actually Portable Executable](https://justine.lol/ape.html): one binary that
runs on Linux, macOS, Windows, FreeBSD, OpenBSD and NetBSD, on both x86_64
and aarch64.

See `AUDIT.md` for the Phase 0 dependency/platform audit and the list of
toolchain quirks discovered along the way.

## Resuming on a fresh server

Everything needed lives in this repo — no state from the previous machine is
required. The build trees (`build-cosmo/`, `build-ref/`) and the `~/cosmos`
sysroot are regenerated from scratch:

```sh
git clone https://github.com/SEBK4C/qlever-cosmopolitan.git
cd qlever-cosmopolitan

# toolchain (~1 GB unpacked)
mkdir -p ~/cosmocc && (cd ~/cosmocc \
  && curl -LO https://cosmo.zip/pub/cosmocc/cosmocc.zip \
  && unzip cosmocc.zip && chmod +x bin/*)

# third-party deps -> ~/cosmos sysroot (takes hours; idempotent and
# resumable — completed deps are skipped via ~/cosmos/.built-* markers)
sh cosmo/build-deps.sh

# QLever itself — this is the resume point, see "Plan & status" below
sh cosmo/build.sh
```

Once `build-cosmo/qlever-index` and `qlever-server` link, continue the
pipeline below from step 3 (`package.sh`, then the parity gate).

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

## Plan & status (as of 2026-06-12)

The port follows the original phase plan. Upstream is pinned at commit
`15bbdad0` of ad-freiburg/qlever.

| Phase | Goal | Status |
|-------|------|--------|
| 0 — pin & audit | Enumerate deps, classify cosmo-compatibility | **Done** — see `AUDIT.md`; zero hard blockers found |
| 1 — toolchain bring-up | CMake toolchain file, deps sysroot | **Done** — `toolchains/cosmocc.cmake`; zlib/zstd/OpenSSL/ICU/Boost all build under cosmocc |
| 2 — de-platform | Replace Linux-only paths, errno/socket compat | **Done** — Boost errno/Asio sentinel+translate patches, ICU `/zip` data embedding, char_traits backport; no Linux-only syscalls remained |
| 3 — conformance & parity | Test suite + index/query parity vs native build | **In progress** — blocked on the first successful link (below) |
| 4 — promote | Ship the APE binary as the primary artifact | Not started |

### Where we left off (2026-06-12, dev moved off a failing-SSD server)

The main QLever compile is **fully green** under cosmocc — all third-party
deps (abseil, ANTLR4, re2, s2, spatialjoin, fsst) and QLever's own sources
compile. The remaining wall is the **final link** of `qlever-index` /
`qlever-server` / `PrintIndexVersionMain`, which was iterating when work
stopped:

- Last symptom: undefined references to
  `absl::synchronization_internal::CreateThreadIdentity` /
  `LowLevelAlloc` — abseil compiled those TUs empty because
  `ABSL_HAVE_MMAP` didn't include `__COSMOPOLITAN__` in its platform list.
- Fix is in place and durable: `cosmo/patch_absl_cosmo.sh`, wired as the
  abseil `PATCH_COMMAND` in the root `CMakeLists.txt`, so a fresh
  FetchContent checkout patches itself automatically.
- The last build with that fix was relaunched but its result was never
  observed (the server died). **The link has not yet been seen to
  succeed** — that is the first thing to verify on the new machine.

### Next steps, in order

1. `sh cosmo/build.sh` — expect the link to go through with the abseil
   fix; if new undefined symbols appear they will likely be the same
   pattern (a dep self-disabling because it doesn't recognize
   `__COSMOPOLITAN__`) — same cure, see `AUDIT.md`.
2. Smoke-test: `build-cosmo/PrintIndexVersionMain`, then
   `sh cosmo/package.sh` to embed ICU data.
3. Parity gate: `bash cosmo/parity-check.sh e2e` (scientists collection +
   70 checked queries; the data self-extracts from
   `e2e/scientist-collection.zip`).
4. Native reference build for cross-diff: configure `build-ref/` with the
   host compiler (needs host ICU/Boost), then
   `bash cosmo/parity-check.sh -r build-ref refe2e crossdiff`.
5. Unit tests: `TARGETS=all sh cosmo/build.sh`, then
   `bash cosmo/parity-check.sh unit`.
6. Once parity is green: revisit jemalloc, then Phase 4 (promote the APE
   binary, set up per-OS CI).
