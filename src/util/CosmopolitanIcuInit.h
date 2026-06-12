// Copyright 2026, University of Freiburg,
// Chair of Algorithms and Data Structures.

#ifndef QLEVER_SRC_UTIL_COSMOPOLITANICUINIT_H
#define QLEVER_SRC_UTIL_COSMOPOLITANICUINIT_H

#ifdef __COSMOPOLITAN__
#include <unistd.h>

#include <cstdlib>

#include <unicode/putil.h>
#endif

namespace ad_utility {

// On Cosmopolitan (APE) builds the ICU data archive (icudt*.dat) is shipped
// inside the executable's embedded zip under `/zip/icu/`. Point ICU there,
// unless the user explicitly overrides the location via the `ICU_DATA`
// environment variable or the archive was not embedded (e.g. plain dev
// builds, where the data is found via `ICU_DATA` instead). Must be called
// before the first ICU operation. A no-op on non-Cosmopolitan builds.
inline void initIcuDataFromExecutable() {
#ifdef __COSMOPOLITAN__
  if (std::getenv("ICU_DATA") == nullptr && access("/zip/icu", F_OK) == 0) {
    u_setDataDirectory("/zip/icu");
  }
#endif
}

}  // namespace ad_utility

#endif  // QLEVER_SRC_UTIL_COSMOPOLITANICUINIT_H
