# QLever → Cosmopolitan port: Phase 0 audit

**Pinned commit:** `15bbdad052a183ddf3a853dab562c741dbf5ee0c`
("Read on-disk vocabulary via `pread` instead of `mmap` (#2931)", 2026-06-10)

**Toolchain:** cosmocc (GCC 14.1.0 portcosmo), fetched 2026-06-11 from
<https://cosmo.zip/pub/cosmocc/cosmocc.zip>, unpacked at `~/cosmocc`.
Sysroot prefix for cosmo-built libraries: `~/cosmos` (see `build-deps.sh`).

QLever requires GCC ≥ 11 — cosmocc's GCC 14.1 passes the project's own
compiler gate, and `CMAKE_CXX_COMPILER_ID` resolves to `GNU`, so no CMake
compiler-check patching is needed.

## Toolchain probe results (all verified on this host, Apple Silicon macOS)

| Feature | Status |
|---|---|
| C++20 coroutines (`co_yield`/`co_await`) | works |
| Exceptions + RTTI | works |
| `std::thread` / atomics (Threads) | works |
| `mmap`/`munmap` file-backed MAP_SHARED | works |
| `madvise` + `MADV_*` | works (needs `_GNU_SOURCE`; g++ defines it implicitly for C++) |
| `std::filesystem` | works |
| APE binaries run natively on the dev host | yes (also via `/bin/sh prog` for CMake/CTest) |
| `__linux__` macro | **not defined** — QLever's `#ifdef __linux__` `mremap` fast path is skipped; the existing portable fallback is used |
| stdin (`-xc -`) compilation | broken in fat mode (documented cosmocc limitation) — irrelevant for CMake builds |

## Third-party dependencies at the pinned commit

### FetchContent (built inside QLever's own CMake — inherit the toolchain)

| Dep | Pin | Language/class | Cosmo risk |
|---|---|---|---|
| googletest | `7917641f` (2025-09-11) | C++ | low (tests only) |
| nlohmann-json | v3.12.0 | header-only | trivial |
| antlr4 runtime | `cc82115a` (4.13.2 line) | C++ static lib | low–medium (utf8 handling, no platform APIs of note) |
| range-v3 (joka921 fork) | `42340ef3` | header-only | trivial |
| spatialjoin | `c358e479` | C++ | low (bzip2/zlib support already disabled via defines) |
| ctre | v3.10.0 | header-only | trivial |
| abseil | `93ac3a4f` (2024-05-16) | C++ | medium — has platform probes (futex, cycle clock); claims Linux personality, expected to map onto cosmo's polyfills |
| s2geometry | 0.11.1 | C++ | low–medium (depends on abseil, OpenSSL) |
| fsst | `b228af63` (2025-05-27) | C++ with x86 SIMD paths | medium — verify arch guards under fat x86_64+aarch64 compile |
| re2 | 2023-11-01 | C++ | low (depends on abseil) |

### find_package (prebuilt into the `~/cosmos` sysroot — see `build-deps.sh`)

| Dep | Version (matches conanfile.txt) | Build approach | Status |
|---|---|---|---|
| zlib (transitive, Boost.Iostreams gzip) | 1.3.1 | `./configure --static` | **built** |
| zstd | 1.5.5 | static lib, `ZSTD_DISABLE_ASM` (x86-only asm vs fat compile) | **built** |
| OpenSSL | 3.1.1 | `linux-generic64 no-asm no-shared no-dso no-module no-engine` | building |
| ICU | 76.1 | static, `--with-data-packaging=archive` (`.dat` destined for `/zip/`) | building |
| Boost | 1.83.0 | b2, static: iostreams, program_options, url, container; asio/beast header-only | building |
| jemalloc | — | **skipped** — optional in QLever's CMake; cosmo's malloc used instead (perf work later) |

## First-party platform-specific code (full sweep of src/, test/, benchmark/)

**Blockers: none.** Work items:

| Severity | Where | Issue | Resolution |
|---|---|---|---|
| resolved | `src/util/MmapVectorImpl.h:85-98,129` | `mremap()` fast path under `#ifdef __linux__` | cosmocc doesn't define `__linux__`; portable fallback already exists and is used |
| low | `src/util/MmapVectorImpl.h:299-305` | `madvise` hints | available under cosmo (g++ implies `_GNU_SOURCE`) |
| low | `src/index/IndexBuilderMain.cpp:138` | hardcoded `/dev/stdin` | cosmo polyfills `/dev/stdin` on all OSes; verify on Windows leg in Phase 3 |
| low | `test/VocabularyGeneratorTest.cpp:80` | `system("mkdir -p …")` | replace with `std::filesystem::create_directories` (test-only) |

Everything else is clean POSIX / standard C++: no epoll/io_uring/eventfd/inotify,
no `/proc` reads, no dlopen, no raw Linux socket options (HTTP stack is pure
Boost.Asio/Beast), no jemalloc-specific API calls, no endianness tricks.
OpenMP is used in one operation (`CountAvailablePredicates`) — cosmocc bundles
LLVM OpenMP; `USE_PARALLEL` falls back cleanly if unavailable.

## The errno problem (solved)

Under Cosmopolitan, errno constants are **runtime symbols** (`extern const
errno_t`) holding host-native values (verified: XNU values on macOS), so they
cannot appear in constant expressions. Two Boost headers put errno macros into
enum initializers and fail to compile (`boost/system/detail/errc.hpp`,
`boost/asio/error.hpp`). Fix, mirroring what cosmocc's libcxx does for
`std::errc` (see `cosmo/gen_errno_compat.py`, `cosmo/patch_boost_cosmo.py`,
applied automatically by `build-deps.sh`):

1. Inside those two headers only, errno macros are temporarily redefined to
   Linux x86_64 numeric sentinels (`push_macro`/`pop_macro` wrapper headers in
   `cosmo/compat/`), so the enums compile.
2. Every funnel where the enums become `error_code`/`error_condition` values
   translates sentinel → native at runtime via `cosmo_compat::native_errno()`:
   `boost::system::errc::make_error_code`/`make_error_condition`, the
   `error_condition(errc_t)` fast-path constructor, and
   `boost::asio::error::make_error_code(basic_errors)`.

Verified end-to-end: an `error_code` built from a failing syscall's native
errno compares equal to `boost::asio::error::*` and `boost::system::errc::*`
constants on this (XNU-errno) host.

**Socket constants, same story:** `SOL_SOCKET`, `SO_*`, `IPV6_*`, `IP_*` and
`AF_INET6` are also runtime symbols (verified: XNU values on macOS —
`SOL_SOCKET=0xffff`, `SO_REUSEADDR=4`), while `AF_INET`, `SOCK_*`,
`IPPROTO_*`, `TCP_NODELAY`, `MSG_PEEK/OOB/DONTROUTE` and `SHUT_*` are
universal literals. Boost.Asio uses the symbolic ones in compile-time
contexts (`socket_base.hpp` enums, `socket_option` template arguments). Fix
(also in `patch_boost_cosmo.py` + `cosmo/compat/cosmo_socket_compat.h`):
the `BOOST_ASIO_OS_DEF_*` macros get Linux sentinels in
`boost/asio/detail/socket_types.hpp`, and `cosmo_compat::native_sockopt()`
translates sentinel→native at Asio's single setsockopt/getsockopt funnel
(`socket_ops.ipp`). `AF_INET6` stays symbolic (only used in runtime
contexts, so the native value flows through). `if_indextoname`/
`if_nametoindex` don't exist under cosmo and are stubbed (numeric IPv6
scope ids still work); `MSG_EOR` doesn't exist and its sentinel is never
translated (`socket_base::message_end_of_record` must not be used).

Related portcosmo (GCC patch) hazard found while probing: a C++
`switch (x) { case EINVAL: return ...; }` on errno constants is **miscompiled**
(rewritten, then traps at runtime); `break`-style switches work. Neither
QLever nor Boost contains `switch (errno)`, but grep build logs for
`rewrote N switch statements` + `-Wswitch-unreachable` as a tripwire.

## ICU data

ICU is built with `--with-data-packaging=archive`, producing
`~/cosmos/share/icu/76.1/icudt76l.dat`. Plan: ship the `.dat` inside the APE
zip (`/zip/icu/`) and call `u_setDataDirectory("/zip/icu")` early in
`IndexBuilderMain`/`ServerMain` (guarded by `__COSMOPOLITAN__`). Until that
patch lands, set `ICU_DATA=$HOME/cosmos/share/icu/76.1` in the environment.

## Phase status

- [x] Phase 0 — pin + audit (this document)
- [x] Phase 1a — toolchain bring-up probes (`toolchains/cosmocc.cmake`)
- [x] Phase 1b — sysroot deps (zlib, zstd, OpenSSL, ICU, Boost — all built;
      Boost with the errno compat patches; ICU collation + Boost errno
      translation verified by standalone probes)
- [ ] Phase 1c/2 — QLever configure ✅ + build ⏳ + de-platform fixes (`cosmo/build.sh`)
- [x] ICU `/zip/` embedding patch (`src/util/CosmopolitanIcuInit.h`, wired into
      the three mains; `cosmo/package.sh` embeds the `.dat`)
- [ ] Phase 3 — parity harness (`cosmo/parity-check.sh`): e2e + unit tests, cosmo build vs reference build
- [ ] Phase 4 — promote (CI integration; out of scope for the local bring-up)
