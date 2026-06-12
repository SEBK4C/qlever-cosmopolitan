#!/bin/sh
# FetchContent PATCH_COMMAND for abseil (runs inside the abseil source dir):
# add Cosmopolitan to the ABSL_HAVE_MMAP platform list. Without it, abseil
# compiles LowLevelAlloc/CreateThreadIdentity as empty TUs while mutex.cc
# (gated on thread-local support instead) still references them -> undefined
# symbols at link time. Idempotent.
set -eu
f=absl/base/config.h
grep -q '__COSMOPOLITAN__' "$f" && exit 0
sed -i.cosmo-bak 's/#elif defined(__linux__) || defined(__APPLE__) || defined(__FreeBSD__) ||    \\/#elif defined(__linux__) || defined(__APPLE__) || defined(__FreeBSD__) ||    \\\n    defined(__COSMOPOLITAN__) ||                                              \\/' "$f"
grep -q '__COSMOPOLITAN__' "$f"
