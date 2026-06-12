// Copyright 2026, University of Freiburg,
// Chair of Algorithms and Data Structures.

#ifndef QLEVER_SRC_UTIL_COSMOPOLITANICUINIT_H
#define QLEVER_SRC_UTIL_COSMOPOLITANICUINIT_H

#ifdef __COSMOPOLITAN__
#include <dirent.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>

#include <unicode/udata.h>
#include <unicode/utypes.h>
#endif

namespace ad_utility {

// On Cosmopolitan (APE) builds the ICU data archive (icudt*.dat) is shipped
// inside the executable's embedded zip under `/zip/icu/`. ICU's default
// loader mmap()s the archive, which fails for deflate-compressed zip
// entries, so instead read the bytes via stdio (which transparently
// decompresses) and hand them to `udata_setCommonData()`. The buffer must
// stay alive for the lifetime of the process. A user-provided `ICU_DATA`
// environment variable takes precedence; plain dev builds without an
// embedded archive keep using it as before. Must be called before the
// first ICU operation. A no-op on non-Cosmopolitan builds.
inline void initIcuDataFromExecutable() {
#ifdef __COSMOPOLITAN__
  if (std::getenv("ICU_DATA") != nullptr) {
    return;
  }
  // Find the (single) .dat archive, whatever ICU version it belongs to.
  std::string path;
  if (DIR* dir = opendir("/zip/icu")) {
    while (dirent* entry = readdir(dir)) {
      size_t len = std::strlen(entry->d_name);
      if (len > 4 && std::strcmp(entry->d_name + len - 4, ".dat") == 0) {
        path = std::string("/zip/icu/") + entry->d_name;
        break;
      }
    }
    closedir(dir);
  }
  if (path.empty()) {
    return;
  }
  std::FILE* file = std::fopen(path.c_str(), "rb");
  if (file == nullptr) {
    return;
  }
  std::fseek(file, 0, SEEK_END);
  long size = std::ftell(file);
  std::fseek(file, 0, SEEK_SET);
  if (size <= 0) {
    std::fclose(file);
    return;
  }
  // Intentionally kept alive forever: ICU references the buffer until exit.
  static std::unique_ptr<char[]> buffer = std::make_unique<char[]>(size);
  size_t numRead = std::fread(buffer.get(), 1, size, file);
  std::fclose(file);
  if (static_cast<long>(numRead) != size) {
    return;
  }
  UErrorCode status = U_ZERO_ERROR;
  udata_setCommonData(buffer.get(), &status);
#endif
}

}  // namespace ad_utility

#endif  // QLEVER_SRC_UTIL_COSMOPOLITANICUINIT_H
