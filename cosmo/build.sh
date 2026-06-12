#!/bin/sh
# Configure and build QLever with the Cosmopolitan toolchain.
# Prerequisites: ~/cosmocc (toolchain) and ~/cosmos (sysroot, see build-deps.sh).
#
#   sh cosmo/build.sh [extra cmake configure args...]
#
# Environment:
#   BUILD_DIR – build directory (default: build-cosmo)
#   TARGETS   – space-separated build targets
#               (default: "qlever-index qlever-server PrintIndexVersionMain")
#   JOBS      – parallelism (default: number of cores)
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/build-cosmo}"
COSMOCC="${COSMOCC:-$HOME/cosmocc}"

# Resolve the system make before touching PATH: cosmocc ships its own APE
# `make`, which CMake cannot spawn directly.
MAKE_PROGRAM="$(command -v make)"

# cosmoranlib & friends exec their underlying tools by bare name.
PATH="$PATH:$COSMOCC/bin"
export PATH
TARGETS="${TARGETS:-qlever-index qlever-server PrintIndexVersionMain}"
JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || nproc)}"

# Precompiled headers don't compose with cosmocc's fat (two-compiler) wrapper.
cmake -S "$REPO_ROOT" -B "$BUILD_DIR" \
  -DCMAKE_TOOLCHAIN_FILE="$REPO_ROOT/toolchains/cosmocc.cmake" \
  -DCMAKE_MAKE_PROGRAM="$MAKE_PROGRAM" \
  -DCMAKE_BUILD_TYPE=Release \
  -DUSE_PRECOMPILED_HEADERS=OFF \
  "$@"

# shellcheck disable=SC2086  # TARGETS is intentionally word-split
cmake --build "$BUILD_DIR" -j"$JOBS" --target $TARGETS
