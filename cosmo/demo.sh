#!/usr/bin/env bash
# Phase 5: local-network demo site — QLever UI + several APE-served datasets.
#
#   bash cosmo/demo.sh            # bring everything up, print URLs
#
# Prerequisites:
#   - APE binaries built and packaged (cosmo/build.sh && cosmo/package.sh)
#   - qlever-control on PATH (`pip install 'qlever==0.5.45'`; 0.5.46+
#     needs python >= 3.12) with dataset dirs under $DEMO_DIR
#   - docker access for the UI (user in the docker group; `sg docker`
#     is used so a fresh login isn't required)
#
# Environment:
#   DEMO_DIR    – dataset workspace (default: ~/qlever-demo)
#   QLEVER_BIN  – qlever-control executable (default: qlever on PATH)
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEMO_DIR="${DEMO_DIR:-$HOME/qlever-demo}"
QLEVER_BIN="${QLEVER_BIN:-qlever}"
HOST_IP="$(hostname -I | awk '{print $1}')"

say() { printf '\n=== %s ===\n' "$*"; }

up() { # up <port> — true if something already listens
  curl -s -o /dev/null --max-time 2 "http://localhost:$1/" 2>/dev/null
}

# ---------------------------------------------------------------- scientists
# Served straight from the e2e index with the APE binary — no Qleverfile.
if ! up 7020; then
  say "starting scientists (APE qlever-server, port 7020)"
  if [ ! -f "$ROOT/e2e_data/scientists-index.vocabulary.words" ]; then
    echo "scientists index missing — run: bash cosmo/parity-check.sh e2e" >&2
  else
    (cd "$ROOT" && ./build-cosmo/qlever-server -i e2e_data/scientists-index \
        -p 7020 -m 2GB -t &>"$DEMO_DIR/scientists-server.log" &)
    sleep 1
  fi
else
  say "scientists already up on 7020"
fi

# ------------------------------------------------------------------ olympics
if ! up 7019; then
  say "starting olympics (qlever-control + APE binaries, port 7019)"
  (cd "$DEMO_DIR/olympics" && "$QLEVER_BIN" start)
else
  say "olympics already up on 7019"
fi

# ------------------------------------------------------------------------ UI
if ! up 8176; then
  say "starting QLever UI (docker)"
  (cd "$DEMO_DIR/olympics" && sg docker -c "$QLEVER_BIN ui")
else
  say "UI already up on 8176"
fi

say "demo ready"
cat <<EOF
  QLever UI:   http://$HOST_IP:8176/olympics
  SPARQL endpoints (POST a query, or open in any SPARQL client):
    olympics:   http://$HOST_IP:7019
    scientists: http://$HOST_IP:7020
  Example (top Olympic medalists, ~30 ms):
    curl -s http://$HOST_IP:7019 -H 'Accept: application/sparql-results+json' \\
      --data-urlencode 'query=PREFIX o: <http://wallscope.co.uk/ontology/olympics/>
        PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
        SELECT ?name (COUNT(*) AS ?medals) WHERE {
          ?i o:athlete ?a . ?a rdfs:label ?name . ?i o:medal ?m
        } GROUP BY ?name ORDER BY DESC(?medals) LIMIT 5'
EOF
