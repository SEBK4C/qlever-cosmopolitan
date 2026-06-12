#!/usr/bin/env bash
# Phase 3 conformance gate: feature parity of the Cosmopolitan build against
# (a) QLever's own e2e expectations and (b) a reference (native) build.
#
#   bash cosmo/parity-check.sh [-c <cosmo-build-dir>] [-r <ref-build-dir>] [stages...]
#
# Stages (default: "e2e crossdiff"):
#   e2e        run e2e/e2e.sh against the cosmo build (expected-results checks
#              from scientists_queries.yaml — ground truth, independent of the
#              reference build)
#   refe2e     run e2e/e2e.sh against the reference build
#   crossdiff  start both servers on their own freshly-built indexes and diff
#              the SPARQL JSON results of all e2e queries (cosmo/query_diff.py)
#   unit       run the unit-test suite of the cosmo build via ctest
#              (requires tests to have been built: cosmo/build.sh with
#               TARGETS=all or the individual test targets)
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COSMO_BUILD="$ROOT/build-cosmo"
REF_BUILD="$ROOT/build-ref"
COSMOS="${COSMOS:-$HOME/cosmos}"

while getopts "c:r:" arg; do
  case $arg in
    c) COSMO_BUILD="$OPTARG" ;;
    r) REF_BUILD="$OPTARG" ;;
    *) exit 2 ;;
  esac
done
shift $((OPTIND - 1))
STAGES="${*:-e2e crossdiff}"

# The cosmo binaries need the ICU data archive until it is embedded in /zip.
ICU_DATA_DIR="$(ls -d "$COSMOS"/share/icu/* 2>/dev/null | head -1 || true)"
[ -n "$ICU_DATA_DIR" ] && export ICU_DATA="$ICU_DATA_DIR"

# Python with PyYAML for queryit.py / query_diff.py.
VENV="$ROOT/.venv-e2e"
if [ ! -x "$VENV/bin/python" ]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" -q install pyyaml
fi
export PYTHON_BINARY="$VENV/bin/python"

rel() { python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$1" "$2"; }

start_server() { # start_server <build-dir> <index-prefix> <port> -> echoes pid
  local dir=$1 index=$2 port=$3
  (cd "$dir" && ./qlever-server -i "$index" -p "$port" -m 1GB -t \
      --default-query-timeout 30s &>"server_log.$port.txt" & echo $!)
}

wait_port() { # wait_port <port>
  for _ in $(seq 1 60); do
    curl --max-time 1 -s -o /dev/null "http://localhost:$1/" && return 0
    sleep 1
  done
  echo "server on port $1 did not come up" >&2
  return 1
}

build_index() { # build_index <build-dir>
  local dir=$1
  local data="$ROOT/e2e/e2e_data"
  mkdir -p "$data"
  if [ ! -f "$data/scientist-collection/scientists.nt" ]; then
    (cd "$data" && unzip -oq "$ROOT/e2e/scientist-collection.zip")
  fi
  local input="$data/scientist-collection/scientists"
  (cd "$dir" &&
    ./qlever-index -i scientists -F ttl -f "$input.nt" \
        -s "$ROOT/e2e/e2e-build-settings.json" \
        -w "$input.wordsfile.tsv" -W -d "$input.docsfile.tsv")
}

for stage in $STAGES; do
  echo "##### stage: $stage #####"
  case $stage in
    e2e)
      (cd "$ROOT" && bash e2e/e2e.sh -d "$(rel "$COSMO_BUILD" "$ROOT")")
      ;;
    refe2e)
      (cd "$ROOT" && bash e2e/e2e.sh -d "$(rel "$REF_BUILD" "$ROOT")")
      ;;
    crossdiff)
      [ -x "$COSMO_BUILD/qlever-index" ] || { echo "no cosmo build"; exit 1; }
      [ -x "$REF_BUILD/qlever-index" ] || { echo "no reference build at $REF_BUILD"; exit 1; }
      build_index "$COSMO_BUILD"
      build_index "$REF_BUILD"
      pid_a=$(start_server "$COSMO_BUILD" scientists 9097)
      pid_b=$(start_server "$REF_BUILD" scientists 9098)
      trap 'kill $pid_a $pid_b 2>/dev/null || true' EXIT
      wait_port 9097
      wait_port 9098
      "$PYTHON_BINARY" "$ROOT/cosmo/query_diff.py" \
        "$ROOT/e2e/scientists_queries.yaml" \
        "http://localhost:9097" "http://localhost:9098"
      kill "$pid_a" "$pid_b" 2>/dev/null || true
      trap - EXIT
      ;;
    unit)
      ctest --test-dir "$COSMO_BUILD" --output-on-failure -j "$(sysctl -n hw.ncpu 2>/dev/null || nproc)"
      ;;
    *)
      echo "unknown stage: $stage" >&2; exit 2 ;;
  esac
done
echo "##### parity check passed for stages: $STAGES #####"
