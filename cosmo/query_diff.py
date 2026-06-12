#!/usr/bin/env python3
"""Cross-build SPARQL result parity check.

Reads the queries from an e2e YAML file (e.g. e2e/scientists_queries.yaml),
sends each one to two QLever server endpoints, and compares the
application/sparql-results+json answers after normalization.

Normalization:
  - result rows are sorted unless the query contains ORDER BY
    (engines are free to return unordered solutions in any order)
  - xsd:double/decimal literal values are compared as floats with a small
    relative tolerance (libm differences across libcs are not parity bugs)

Exit code 0 iff all queries agree.
"""

import argparse
import json
import math
import re
import sys
import urllib.parse
import urllib.request

import yaml

FLOAT_TYPES = {
    "http://www.w3.org/2001/XMLSchema#double",
    "http://www.w3.org/2001/XMLSchema#decimal",
    "http://www.w3.org/2001/XMLSchema#float",
}
REL_TOL = 1e-9


def run_query(endpoint: str, sparql: str, timeout: int):
    data = urllib.parse.urlencode({"query": sparql}).encode()
    req = urllib.request.Request(
        endpoint,
        data=data,
        headers={
            "Content-Type": "application/x-www-form-urlencoded",
            "Accept": "application/sparql-results+json",
        },
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.load(resp)


def canonical_binding(b):
    out = {}
    for var, val in sorted(b.items()):
        v = dict(val)
        if v.get("datatype") in FLOAT_TYPES:
            try:
                v["value"] = float(v["value"])
            except ValueError:
                pass
        out[var] = v
    return out


def rows_equal(a, b):
    if set(a.keys()) != set(b.keys()):
        return False
    for var in a:
        va, vb = a[var], b[var]
        if isinstance(va.get("value"), float) and isinstance(vb.get("value"), float):
            ka = {k: v for k, v in va.items() if k != "value"}
            kb = {k: v for k, v in vb.items() if k != "value"}
            if ka != kb:
                return False
            if not math.isclose(va["value"], vb["value"], rel_tol=REL_TOL):
                return False
        elif va != vb:
            return False
    return True


def sort_key(row):
    return json.dumps(row, sort_keys=True, default=str)


def compare(name, query, res_a, res_b):
    head_a = sorted(res_a.get("head", {}).get("vars", []))
    head_b = sorted(res_b.get("head", {}).get("vars", []))
    if head_a != head_b:
        return f"head mismatch: {head_a} vs {head_b}"
    rows_a = [canonical_binding(b) for b in res_a["results"]["bindings"]]
    rows_b = [canonical_binding(b) for b in res_b["results"]["bindings"]]
    if len(rows_a) != len(rows_b):
        return f"row count mismatch: {len(rows_a)} vs {len(rows_b)}"
    ordered = re.search(r"ORDER\s+BY", query, re.IGNORECASE)
    if not ordered:
        rows_a.sort(key=sort_key)
        rows_b.sort(key=sort_key)
    for i, (ra, rb) in enumerate(zip(rows_a, rows_b)):
        if not rows_equal(ra, rb):
            return (
                f"row {i} differs:\n  A: {json.dumps(ra, sort_keys=True)}"
                f"\n  B: {json.dumps(rb, sort_keys=True)}"
            )
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("yaml_file")
    ap.add_argument("endpoint_a")
    ap.add_argument("endpoint_b")
    ap.add_argument("--timeout", type=int, default=60)
    args = ap.parse_args()

    with open(args.yaml_file) as f:
        spec = yaml.safe_load(f)

    queries = spec["queries"]
    failures = 0
    skipped = 0
    for entry in queries:
        name = entry.get("query", "<unnamed>")
        sparql = entry.get("sparql")
        if not sparql:
            skipped += 1
            continue
        try:
            res_a = run_query(args.endpoint_a, sparql, args.timeout)
        except Exception as e:  # noqa: BLE001
            print(f"FAIL {name}: endpoint A error: {e}")
            failures += 1
            continue
        try:
            res_b = run_query(args.endpoint_b, sparql, args.timeout)
        except Exception as e:  # noqa: BLE001
            print(f"FAIL {name}: endpoint B error: {e}")
            failures += 1
            continue
        if "results" not in res_a or "results" not in res_b:
            # e.g. CONSTRUCT queries return a different format; compare raw.
            if res_a != res_b:
                print(f"FAIL {name}: non-SELECT results differ")
                failures += 1
            continue
        diff = compare(name, sparql, res_a, res_b)
        if diff:
            print(f"FAIL {name}: {diff}")
            failures += 1
        else:
            print(f"ok   {name}")

    total = len(queries) - skipped
    print(f"\n{total - failures}/{total} queries agree ({skipped} skipped, no sparql)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
