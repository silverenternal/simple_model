#!/usr/bin/env bash
set -euo pipefail
INPUT=""; OUT="generated/intelligence/runtime-evidence-compact.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --input|-i) INPUT="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac; done
[[ -f "$INPUT" ]] || { echo "--input required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq '{schema_version:"2.0",ok:true,observations:(.observations|group_by(.edge_id)|map(.[0] + {sample_count:length,sampling:([.[].sampling]|add/length),coverage:([.[].coverage]|max)})),summary:(.summary + {compacted:true})}' "$INPUT" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Compacted runtime edges=\(.observations|length)"' "$OUT"; fi
