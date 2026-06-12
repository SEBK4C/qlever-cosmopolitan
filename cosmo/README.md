# QLever on Cosmopolitan Libc

This directory contains everything needed to build QLever as an
[Actually Portable Executable](https://justine.lol/ape.html): one binary that
runs on Linux, macOS, Windows, FreeBSD, OpenBSD and NetBSD, on both x86_64
and aarch64.

See `AUDIT.md` for the Phase 0 dependency/platform audit and the list of
toolchain quirks discovered along the way. End-user instructions for the
released binaries live in `USAGE.md`.

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
| 3 — conformance & parity | Test suite + index/query parity vs native build | **e2e green** ✅ (2026-06-12) — all 220 expected-results checks pass against the cosmo build; crossdiff vs native + unit tests still open |
| 4 — promote | Ship the APE binary as the primary artifact | **Started** — first release published; per-OS CI still open |

### Status (2026-06-12, rebuilt from scratch on a fresh server)

The full pipeline through step 3 is green, end to end, on a clean machine:

- Sysroot rebuilt from nothing (`build-deps.sh`) — three latent bugs in the
  fresh-server path were found and fixed along the way (ICU makefile
  self-clobber, Boost b2 bootstrap without a host compiler, plus a
  toolchain-extraction symlink trap). Details in `AUDIT.md` under
  "Fresh-server bring-up quirks".
- **The final link succeeded** — `qlever-index` (113 MB), `qlever-server`
  (117 MB) and `PrintIndexVersionMain` all link with the abseil
  `ABSL_HAVE_MMAP` patch; no further undefined-symbol rounds were needed.
- Smoke tests pass: `PrintIndexVersionMain` prints its version JSON,
  `qlever-server --help` works.
- `package.sh` ran: `icudt76l.dat` is embedded in both binaries' zip
  sections.
- **The e2e parity gate passed** — but only after it caught two real
  runtime bugs that the smoke tests missed: cosmo's 80 KiB default thread
  stacks (segfault on recursive query execution) and ICU being unable to
  mmap its deflated `/zip` data archive (`U_FILE_ACCESS_ERROR` without
  `ICU_DATA`). Both fixed in source; see AUDIT quirks #6/#7 and
  `REPORT-2026-06-12.md` for the full narrative.

### Next steps, in order

1. Native reference build for cross-diff: configure `build-ref/` with the
   host compiler (needs host toolchain + ICU/Boost, e.g.
   `apt install build-essential libicu-dev libboost-all-dev libssl-dev
   libzstd-dev zlib1g-dev`), then
   `bash cosmo/parity-check.sh -r build-ref refe2e crossdiff`.
2. Unit tests: `TARGETS=all sh cosmo/build.sh`, then
   `bash cosmo/parity-check.sh unit`.
3. Run the e2e gate on at least one non-Linux host (macOS/Windows) with
   the released binaries.
4. Revisit jemalloc, then finish Phase 4 (per-OS CI).
