// Copyright 2026, University of Freiburg,
// Chair of Algorithms and Data Structures.

#ifndef QLEVER_SRC_UTIL_COSMOPOLITANTHREADSTACK_H
#define QLEVER_SRC_UTIL_COSMOPOLITANTHREADSTACK_H

// Cosmopolitan's default pthread stack size is 80 KiB (glibc: 8 MiB).
// QLever executes query trees recursively (Operation::runComputation ->
// child operations) and serializes RuntimeInformation recursively, which
// overflows such small stacks on perfectly ordinary queries — observed as
// a SIGSEGV one page below the stack mapping during the e2e suite.
//
// `toolchains/cosmocc.cmake` links every executable with
// `-Wl,--wrap=pthread_create`; the wrapper below floors the stack size of
// every created thread at 8 MiB (raising it leaves address space mostly
// uncommitted, so the cost is virtual only). std::thread, boost::asio and
// abseil all funnel through pthread_create, so this covers them all.
//
// This header must be included by exactly one translation unit per
// executable — the `main` TUs — so the symbol is defined in the first
// object on the link line and resolves references from all archives that
// follow. It defines a non-inline function: do not include it elsewhere.

#ifdef __COSMOPOLITAN__
#include <pthread.h>

#include <cstddef>

extern "C" int __real_pthread_create(pthread_t* thread,
                                     const pthread_attr_t* attr,
                                     void* (*startRoutine)(void*), void* arg);

extern "C" int __wrap_pthread_create(pthread_t* thread,
                                     const pthread_attr_t* attr,
                                     void* (*startRoutine)(void*), void* arg) {
  constexpr size_t kMinStackSize = 8 * 1024 * 1024;
  pthread_attr_t localAttr;
  if (attr == nullptr) {
    pthread_attr_init(&localAttr);
  } else {
    localAttr = *attr;
  }
  size_t stackSize = 0;
  pthread_attr_getstacksize(&localAttr, &stackSize);
  if (stackSize < kMinStackSize) {
    pthread_attr_setstacksize(&localAttr, kMinStackSize);
  }
  int result = __real_pthread_create(thread, &localAttr, startRoutine, arg);
  if (attr == nullptr) {
    pthread_attr_destroy(&localAttr);
  }
  return result;
}
#endif

#endif  // QLEVER_SRC_UTIL_COSMOPOLITANTHREADSTACK_H
