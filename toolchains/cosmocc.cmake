# CMake toolchain file for building QLever with the Cosmopolitan toolchain
# (https://github.com/jart/cosmopolitan, cosmocc). Produces Actually Portable
# Executables (APE) that run on Linux/macOS/Windows/*BSD on x86_64 + aarch64.
#
# Usage:
#   cmake -DCMAKE_TOOLCHAIN_FILE=toolchains/cosmocc.cmake \
#         -DCMAKE_PREFIX_PATH=$HOME/cosmos ...
#
# Environment overrides:
#   COSMOCC  – root of the unpacked cosmocc toolchain (default: $HOME/cosmocc)
#   COSMOS   – sysroot prefix with cosmo-built third-party libs (default: $HOME/cosmos)

if(DEFINED ENV{COSMOCC})
    set(COSMOCC_ROOT "$ENV{COSMOCC}")
else()
    set(COSMOCC_ROOT "$ENV{HOME}/cosmocc")
endif()
if(DEFINED ENV{COSMOS})
    set(COSMOS_PREFIX "$ENV{COSMOS}")
else()
    set(COSMOS_PREFIX "$ENV{HOME}/cosmos")
endif()

if(NOT EXISTS "${COSMOCC_ROOT}/bin/cosmocc")
    message(FATAL_ERROR "cosmocc not found at ${COSMOCC_ROOT}/bin/cosmocc. "
            "Download it from https://cosmo.zip/pub/cosmocc/cosmocc.zip and unpack, "
            "or set the COSMOCC environment variable.")
endif()

# Cosmopolitan presents a mostly-Linux personality at the libc level. Claiming
# Linux here avoids the APPLE-specific (Homebrew) and native-Windows branches
# in CMake and in project CMakeLists, and puts CMake into cross-compiling mode
# so it never leaks host (e.g. Homebrew) libraries into the build.
set(CMAKE_SYSTEM_NAME Linux)
# Nominal value; cosmocc builds fat x86_64+aarch64 binaries in one pass.
set(CMAKE_SYSTEM_PROCESSOR x86_64)

set(CMAKE_C_COMPILER   "${COSMOCC_ROOT}/bin/cosmocc")
set(CMAKE_CXX_COMPILER "${COSMOCC_ROOT}/bin/cosmoc++")
set(CMAKE_AR           "${COSMOCC_ROOT}/bin/cosmoar" CACHE FILEPATH "ar")
# cosmoranlib is a #!/bin/sh wrapper (execve-able everywhere) that execs
# x86_64-linux-cosmo-ranlib by bare name — the toolchain bin dir must be on
# PATH (cosmo/build.sh does this). The raw *-cosmo-ranlib binaries are APE
# files that cannot be spawned directly by CMake's link-script runner.
set(CMAKE_RANLIB       "${COSMOCC_ROOT}/bin/cosmoranlib" CACHE FILEPATH "ranlib")

# APE binaries cannot be execve()'d directly by CMake/CTest on all hosts (the
# kernel returns ENOEXEC for the shell-script header); launching them through
# sh is the canonical workaround and works everywhere.
set(CMAKE_CROSSCOMPILING_EMULATOR "/bin/sh")

# Cosmopolitan is a static-only world: no shared objects, no dlopen.
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(Boost_USE_STATIC_LIBS ON)
set(Boost_USE_STATIC_RUNTIME ON)
set(CMAKE_FIND_LIBRARY_SUFFIXES ".a")
set(CMAKE_POSITION_INDEPENDENT_CODE OFF)
set(CMAKE_EXE_LINKER_FLAGS_INIT "-static -L${COSMOS_PREFIX}/lib")

# Make the sysroot headers (zlib.h, the cosmo_compat errno shims included by
# the patched Boost headers, …) visible to every TU, including third-party
# FetchContent code that hard-includes them.
set(CMAKE_C_FLAGS_INIT "-isystem ${COSMOS_PREFIX}/include")
# -include iterator: cosmocc's libcxx has stricter transitive includes than
# libstdc++; some third-party code (e.g. spatialjoin) uses std::inserter
# et al. without including <iterator>.
# BOOST_ASIO_DISABLE_SERIAL_PORT: the termios baud-rate constants (B50, …)
# are runtime symbols under Cosmopolitan and Asio's serial-port code puts
# them in switch cases; QLever doesn't use serial ports.
set(CMAKE_CXX_FLAGS_INIT "-isystem ${COSMOS_PREFIX}/include -include iterator -DBOOST_ASIO_DISABLE_SERIAL_PORT")

# Only search the cosmo sysroot for libraries/headers; never the host system.
set(CMAKE_FIND_ROOT_PATH "${COSMOS_PREFIX}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
list(APPEND CMAKE_PREFIX_PATH "${COSMOS_PREFIX}")

# Everything is linked statically with the single-pass GNU ld.bfd; wrap the
# whole library list in one group so inter-archive ordering (abseil internals,
# ICU, OpenSSL) can never produce undefined references.
set(CMAKE_CXX_LINK_EXECUTABLE
    "<CMAKE_CXX_COMPILER> <FLAGS> <CMAKE_CXX_LINK_FLAGS> <LINK_FLAGS> <OBJECTS> -o <TARGET> -Wl,--start-group <LINK_LIBRARIES> -Wl,--end-group")
set(CMAKE_C_LINK_EXECUTABLE
    "<CMAKE_C_COMPILER> <FLAGS> <CMAKE_C_LINK_FLAGS> <LINK_FLAGS> <OBJECTS> -o <TARGET> -Wl,--start-group <LINK_LIBRARIES> -Wl,--end-group")

# pkg-config (used for the optional jemalloc lookup) must not find host libs.
set(ENV{PKG_CONFIG_LIBDIR} "${COSMOS_PREFIX}/lib/pkgconfig")
set(ENV{PKG_CONFIG_PATH} "")
