#!/usr/bin/env bash
set -euo pipefail
SESSION=""; OUT="generated/intelligence/mql-repl.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --session) SESSION="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac; done
[[ -f "$SESSION" ]] || { echo "--session required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq '{schema_version:"1.0",ok:true,session_id:.session_id,answers:(.queries//[]),handoff:.handoff,policy:.policy}' "$SESSION" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"MQL REPL answers=\(.answers|length)"' "$OUT"; fi
