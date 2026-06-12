#!/bin/sh
# Build QLever's find_package() dependencies with the Cosmopolitan toolchain
# into a sysroot prefix ($COSMOS, default ~/cosmos). Idempotent: each dep
# leaves a .built-<name> marker in the prefix and is skipped on re-runs.
#
# Versions are pinned to match conanfile.txt at the pinned QLever commit
# (boost 1.83.0, icu 76.1, openssl 3.1.1, zstd 1.5.5) + zlib 1.3.1 for
# Boost.Iostreams' gzip filter.
#
# jemalloc is intentionally NOT built: it is optional in QLever's CMake and
# cosmo's own malloc is used instead (swap-in is a later optimization).
set -eu

COSMOCC="${COSMOCC:-$HOME/cosmocc}"
COSMOS="${COSMOS:-$HOME/cosmos}"
JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || nproc)}"
SRCDIR="$COSMOS/src"
LOGDIR="$COSMOS/log"

mkdir -p "$COSMOS" "$SRCDIR" "$LOGDIR" "$COSMOS/lib/pkgconfig"

# cosmoranlib & friends exec their underlying tools by bare name.
PATH="$COSMOCC/bin:$PATH"
export PATH

CC="$COSMOCC/bin/cosmocc"
CXX="$COSMOCC/bin/cosmoc++"
AR="$COSMOCC/bin/cosmoar"
RANLIB="$COSMOCC/bin/cosmoranlib"
INSTALL="$COSMOCC/bin/cosmoinstall"

say() { printf '\n=== %s ===\n' "$*"; }

fetch() { # fetch <url> <tarball-name>
  if [ ! -f "$SRCDIR/$2" ]; then
    say "downloading $2"
    curl -fL --retry 3 -o "$SRCDIR/$2.tmp" "$1"
    mv "$SRCDIR/$2.tmp" "$SRCDIR/$2"
  fi
}

extract() { # extract <tarball> <dirname>
  if [ ! -d "$SRCDIR/$2" ]; then
    say "extracting $1"
    (cd "$SRCDIR" && tar xf "$1")
  fi
}

##############################################################################
# zlib 1.3.1 (for Boost.Iostreams gzip)
##############################################################################
if [ ! -f "$COSMOS/.built-zlib" ]; then
  fetch https://zlib.net/fossils/zlib-1.3.1.tar.gz zlib-1.3.1.tar.gz
  extract zlib-1.3.1.tar.gz zlib-1.3.1
  say "building zlib"
  (
    cd "$SRCDIR/zlib-1.3.1"
    CC="$CC" AR="$AR" RANLIB="$RANLIB" ./configure --prefix="$COSMOS" --static
    make -j"$JOBS" libz.a
    make install
  ) >"$LOGDIR/zlib.log" 2>&1
  touch "$COSMOS/.built-zlib"
fi
echo "zlib: OK"

##############################################################################
# zstd 1.5.5 (static lib only; x86 asm disabled for the fat x86_64+aarch64 build)
##############################################################################
if [ ! -f "$COSMOS/.built-zstd" ]; then
  fetch https://github.com/facebook/zstd/releases/download/v1.5.5/zstd-1.5.5.tar.gz zstd-1.5.5.tar.gz
  extract zstd-1.5.5.tar.gz zstd-1.5.5
  say "building zstd"
  (
    cd "$SRCDIR/zstd-1.5.5/lib"
    make -j"$JOBS" libzstd.a CC="$CC" AR="$AR" RANLIB="$RANLIB" \
      CPPFLAGS="-DZSTD_DISABLE_ASM" ZSTD_NO_ASM=1
    make install-static install-includes install-pc PREFIX="$COSMOS" \
      CC="$CC" AR="$AR" RANLIB="$RANLIB" CPPFLAGS="-DZSTD_DISABLE_ASM" ZSTD_NO_ASM=1
  ) >"$LOGDIR/zstd.log" 2>&1
  touch "$COSMOS/.built-zstd"
fi
echo "zstd: OK"

##############################################################################
# OpenSSL 3.1.1 (static, no-asm: the perl-generated asm is per-arch and
# incompatible with cosmocc's fat single-pass compilation)
##############################################################################
if [ ! -f "$COSMOS/.built-openssl" ]; then
  fetch https://github.com/openssl/openssl/releases/download/openssl-3.1.1/openssl-3.1.1.tar.gz openssl-3.1.1.tar.gz
  extract openssl-3.1.1.tar.gz openssl-3.1.1
  say "building openssl"
  (
    cd "$SRCDIR/openssl-3.1.1"
    [ -f Makefile ] && make distclean >/dev/null 2>&1 || true
    CC="$CC" AR="$AR" RANLIB="$RANLIB" \
      ./Configure linux-generic64 no-asm no-shared no-dso no-module \
        no-engine no-afalgeng no-tests \
        --prefix="$COSMOS" --libdir=lib
    make -j"$JOBS" build_libs
    make install_dev
  ) >"$LOGDIR/openssl.log" 2>&1
  touch "$COSMOS/.built-openssl"
fi
echo "openssl: OK"

##############################################################################
# ICU 76.1 (static; data packaged as a standalone .dat archive so it can be
# embedded into the APE's /zip later). The --host triple selects the mh-linux
# build fragment; since APE binaries run natively on this host, autoconf
# still detects a non-cross build and ICU's build-time tools just work.
##############################################################################
if [ ! -f "$COSMOS/.built-icu" ]; then
  fetch https://github.com/unicode-org/icu/releases/download/release-76-1/icu4c-76_1-src.tgz icu4c-76_1-src.tgz
  extract icu4c-76_1-src.tgz icu
  say "building icu"
  (
    cd "$SRCDIR/icu/source"
    CC="$CC" CXX="$CXX" AR="$AR" RANLIB="$RANLIB" \
      ./configure --host=x86_64-unknown-linux-gnu --prefix="$COSMOS" \
        --enable-static --disable-shared --disable-samples --disable-tests \
        --disable-extras --disable-icuio --with-data-packaging=archive
    # Pre-create the -include'd svchook.mk. make otherwise generates it
    # mid-build with a fresh mtime; common/Makefile lists it as a prerequisite
    # of itself, so the regeneration rule re-runs config.status and clobbers
    # the sed edits below (the rule's normal output for "no localsvc.cpp" is
    # exactly this comment line).
    echo '# Autogenerated by Makefile' > common/svchook.mk
    # cosmocc's wrapper can't pass arguments containing quotes/spaces. Strip
    # the two quoted-string -D defines from the generated makefiles; both are
    # irrelevant here (plugins are unused, and the ICU data location is set at
    # runtime via ICU_DATA / u_setDataDirectory instead of a baked-in path).
    grep -rl -e 'DEFAULT_ICU_PLUGINS' -e 'U_ICU_DATA_DEFAULT_DIR' \
        --include=Makefile --include='*.mk' . \
      | xargs sed -i.cosmo-bak \
          -e '/-DDEFAULT_ICU_PLUGINS=/d' \
          -e '/-DU_ICU_DATA_DEFAULT_DIR=/d'
    make -j"$JOBS"
    make install
  ) >"$LOGDIR/icu.log" 2>&1
  touch "$COSMOS/.built-icu"
fi
echo "icu: OK"

##############################################################################
# Boost 1.83.0 (static: iostreams, program_options, url, container;
# everything else QLever uses — asio, beast, multiprecision — is header-only)
##############################################################################
if [ ! -f "$COSMOS/.built-boost" ]; then
  fetch https://archives.boost.io/release/1.83.0/source/boost_1_83_0.tar.gz boost_1_83_0.tar.gz
  extract boost_1_83_0.tar.gz boost_1_83_0
  say "building boost"
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  (
    cd "$SRCDIR/boost_1_83_0"
    # errno constants are runtime symbols under Cosmopolitan; install the
    # compat headers and patch boost/system + boost/asio accordingly.
    mkdir -p "$COSMOS/include/cosmo_compat"
    cp "$SCRIPT_DIR/compat/cosmo_compat/"*.h "$COSMOS/include/cosmo_compat/"
    python3 "$SCRIPT_DIR/patch_boost_cosmo.py" .
    # bootstrap.sh builds the b2 engine with a host C++ compiler; on hosts
    # without one, build it with cosmoc++ and assimilate the APE result into
    # a native executable (CMake/B2 can't be spawned as APE on bare hosts).
    if [ ! -x ./b2 ]; then
      if command -v c++ >/dev/null 2>&1 || command -v g++ >/dev/null 2>&1 \
         || command -v clang++ >/dev/null 2>&1; then
        ./bootstrap.sh
      else
        (cd tools/build/src/engine && ./build.sh cxx --cxx="$CXX")
        cp tools/build/src/engine/b2 ./b2
        sh "$COSMOCC/bin/assimilate" -x ./b2
      fi
    fi
    cat > cosmo-config.jam <<EOF
using gcc : cosmo : "$CXX" : <archiver>"$AR" <ranlib>"$RANLIB" ;
EOF
    ./b2 --user-config=cosmo-config.jam toolset=gcc-cosmo target-os=linux \
      link=static runtime-link=static threading=multi variant=release \
      architecture= instruction-set= pch=off \
      include="$COSMOS/include" \
      --layout=system --prefix="$COSMOS" \
      --with-iostreams --with-program_options --with-url --with-container \
      -sNO_BZIP2=1 -sNO_LZMA=1 -sNO_ZSTD=1 \
      -sZLIB_INCLUDE="$COSMOS/include" -sZLIB_LIBPATH="$COSMOS/lib" -sZLIB_NAME=z \
      -j"$JOBS" install
  ) >"$LOGDIR/boost.log" 2>&1
  touch "$COSMOS/.built-boost"
fi
echo "boost: OK"

##############################################################################
# Install the aarch64 twin archives. cosmoar writes them to .aarch64/ next to
# each build output, but the deps' `make install` steps only copy the x86_64
# archive; cosmocc's aarch64 link pass searches <libdir>/.aarch64/.
##############################################################################
mkdir -p "$COSMOS/lib/.aarch64"
for a in "$COSMOS"/lib/*.a; do
  base="$(basename "$a")"
  if [ ! -f "$COSMOS/lib/.aarch64/$base" ]; then
    twin="$(find "$SRCDIR" -path "*/.aarch64/$base" 2>/dev/null | head -1)"
    if [ -n "$twin" ]; then
      cp "$twin" "$COSMOS/lib/.aarch64/$base"
      echo "installed .aarch64/$base"
    else
      echo "WARNING: no aarch64 twin found for $base" >&2
    fi
  fi
done

say "sysroot complete at $COSMOS"
ls "$COSMOS/lib"
