#!/usr/bin/env bash
set -euo pipefail
INPUT=""; OUT="generated/intelligence/test-obligations.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --input|-i) INPUT="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac; done
[[ -f "$INPUT" ]] || { echo "--input required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq '{schema_version:"1.0",ok:true,obligations:([.contracts[]? | {id:("contract-test:"+.id),graph_paths:(.graph_paths//[]),assertion_source:(.assertion_source//"explicit_contract"),label:(.label//"contract")}]),summary:{obligations:([.contracts[]?]|length),unlabeled_characterization_assertions:([.contracts[]?|select((.label//"")=="characterization" and ((.labeled//false)|not))]|length)}}' "$INPUT" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Test obligations=\(.summary.obligations)"' "$OUT"; fi
