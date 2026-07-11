#!/usr/bin/env bash
set -euo pipefail
INPUT=""; OUT="generated/daemon/invalidation.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --input|-i) INPUT="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac; done
[[ -f "$INPUT" ]] || { echo "--input required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq '{schema_version:"1.0",ok:true,changed_files:(.changed_files|unique|sort),invalidated_partitions:( [.changed_files[]|if test("struct|graph|src/") then "graph" elif test("test") then "tests" elif test("macro") then "macros" else "drift" end] | unique|sort),coalesced:true}' "$INPUT" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Invalidated=\(.invalidated_partitions|join(\",\"))"' "$OUT"; fi
