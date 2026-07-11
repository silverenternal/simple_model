#!/usr/bin/env bash
set -euo pipefail
INPUT=""; OUT="generated/intelligence/fuzz-target.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --input|-i) INPUT="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac; done
[[ -f "$INPUT" ]] || { echo "--input required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq '{schema_version:"1.0",ok:true,target:{name:(.name//"fuzz_target"),seed_corpus:(.seed_corpus//[]),resource_limits:(.resource_limits//{timeout_ms:1000,memory_mb:256}),reproducibility:{seed:(.seed//0),toolchain:(.toolchain//"pinned")}},ai_leaf_task:{typed:true,review_required:true}}' "$INPUT" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Fuzz target \(.target.name)"' "$OUT"; fi
