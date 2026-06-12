#!/bin/sh
# Embed the ICU data archive into the APE binaries' zip section (/zip/icu/),
# making them fully self-contained. Run after cosmo/build.sh.
#
#   sh cosmo/package.sh [build-dir]
set -eu

COSMOS="${COSMOS:-$HOME/cosmos}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${1:-$REPO_ROOT/build-cosmo}"

# APE zips need the cosmos-modified Info-ZIP (plain zip mangles the APE header).
ZIP="$COSMOS/bin/zip"
if [ ! -x "$ZIP" ]; then
  mkdir -p "$COSMOS/bin"
  curl -fL --retry 3 -o "$ZIP" https://cosmo.zip/pub/cosmos/bin/zip
  chmod +x "$ZIP"
fi

DAT="$(ls "$COSMOS"/share/icu/*/icudt*.dat 2>/dev/null | head -1)"
if [ -z "$DAT" ]; then
  echo "no ICU data archive found under $COSMOS/share/icu — run cosmo/build-deps.sh first" >&2
  exit 1
fi

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
mkdir -p "$STAGING/icu"
cp "$DAT" "$STAGING/icu/"

for bin in qlever-index qlever-server VocabularyMergerMain; do
  target="$BUILD_DIR/$bin"
  [ -f "$target" ] || continue
  if sh -c "cd '$STAGING' && exec sh '$ZIP' -q '$target' 'icu/$(basename "$DAT")'"; then
    echo "embedded $(basename "$DAT") into $bin"
  else
    echo "failed to embed ICU data into $bin" >&2
    exit 1
  fi
done
