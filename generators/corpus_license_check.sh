#!/usr/bin/env bash
set -euo pipefail
MANIFEST=""; OUT="generated/benchmarks/external-corpus/license-report.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --manifest|-m) MANIFEST="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac; done
[[ -f "$MANIFEST" ]] || { echo "--manifest required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq '{schema_version:"2.0",ok:all(.entries[];.license|IN("MIT","Apache-2.0","BSD-3-Clause","ISC")),entries:(.entries|length),redistribution_violations:([.entries[]|select(.permitted_redistribution!=true)]|length),private_source_leaks:([.entries[]|select(.private==true and .source_retained==true)]|length)}' "$MANIFEST" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Corpus license ok=\(.ok)"' "$OUT"; fi
jq -e '.ok==true and .redistribution_violations==0 and .private_source_leaks==0' "$OUT" >/dev/null
