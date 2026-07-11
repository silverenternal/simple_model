#!/usr/bin/env bash
set -euo pipefail
INPUT=""; OUT="generated/intelligence/mined-runtime-contract.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --input|-i) INPUT="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac; done
[[ -f "$INPUT" ]] || { echo "--input required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq '{schema_version:"1.0",contract_id:(.contract_id//"runtime-contract"),status:(if ([.observations[]?|.environment]|unique|length)>=2 then "reviewed" else "provisional" end),observations:([.observations[]?|{environment,build,commit,route,event,error_shape,side_effects,latency_ms}]),normalization:{ignored_fields:["latency_ms","host"],semantic_fields:["route","event","error_shape","side_effects"]},provenance:{source:"runtime_contract_mine",environments:([.observations[]?|.environment]|unique|sort),freshness:"current"},summary:{observations:([.observations[]?]|length),environments:([.observations[]?|.environment]|unique|length)}}' "$INPUT" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Mined contract \(.contract_id) status=\(.status)"' "$OUT"; fi
