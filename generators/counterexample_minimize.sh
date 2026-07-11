#!/usr/bin/env bash
set -euo pipefail
INPUT=""; OUT="generated/macros/minimized-counterexample.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in --input|-i) INPUT="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac
done
[[ -f "$INPUT" ]] || { echo "--input is required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq '{schema_version:"1.0",ok:true,macro_id,proof_obligation,input,expected,observed,resolved:(.resolved//false),regression_fixture:true,original_hash:(tojson|@base64)}' "$INPUT" > "$OUT"
hash="$(jq -S -c 'del(.original_hash)' "$OUT" | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $1}')"
jq --arg hash "$hash" '.counterexample_hash=$hash | .minimization={strategy:"structural-fields-then-scalar",stable:true}' "$OUT" > "$OUT.tmp"; mv "$OUT.tmp" "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Counterexample \(.counterexample_hash)"' "$OUT"; fi
