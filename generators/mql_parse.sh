#!/usr/bin/env bash
set -euo pipefail
INPUT=""; OUT=""; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --input|-i) INPUT="$2"; shift 2;; --output|-o) OUT="$2"; shift 2;; --json) JSON_OUT=1; shift;; *) echo "unknown arg: $1" >&2; exit 64;; esac; done
[[ -f "$INPUT" ]] || { echo "--input JSON query required" >&2; exit 64; }
query="$(jq -S 'if .schema_version=="1.0" and (.match|type)=="object" and (.capture|test("^[a-z][a-z0-9_]*$")) and (.quantifier|IN("any","all","count")) then . else error("invalid MQL query") end' "$INPUT")" || exit 2
captures="$(jq '[.capture, .traverse.capture?]|map(select(.!=null))' <<<"$query")"
[[ "$(jq 'length == (unique|length)' <<<"$captures")" == true ]] || { echo "ambiguous duplicate capture" >&2; exit 3; }
if [[ -n "$OUT" ]]; then printf '%s\n' "$query" > "$OUT"; else printf '%s\n' "$query"; fi
