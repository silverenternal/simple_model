#!/usr/bin/env bash
set -euo pipefail
INPUT=""; OUT="generated/intelligence/golden-contract.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in --input|-i) INPUT="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac
done
[[ -f "$INPUT" ]] || { echo "--input is required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq '
  . as $input
  | ($input.examples // []) as $examples
  | {schema_version:"1.0",ok:true,mode:($input.mode // "exact"),before:($examples[0].before // null),after:($examples[0].after // null),normalizers:($input.normalizers // []),evidence:{examples:($examples|length),source:"golden_contract_miner",stable:true}}
' "$INPUT" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Golden contract examples=\(.evidence.examples)"' "$OUT"; fi
