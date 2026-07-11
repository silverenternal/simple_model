#!/usr/bin/env bash
set -euo pipefail
INPUT=""; OUT="generated/intelligence/reliability-surface.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --input|-i) INPUT="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac; done
[[ -f "$INPUT" ]] || { echo "--input required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq '{schema_version:"1.0",ok:true,chain:(.calls//[]),policies:{non_idempotent_retry:"blocked_without_evidence",timeout_propagation:true,cancellation:true},macros:[{id:"reliability.timeout",simulate_capable:true,apply_capable:true},{id:"reliability.cancellation",simulate_capable:true,apply_capable:true},{id:"reliability.idempotency",simulate_capable:true,apply_capable:false}],summary:{simulate_capable_macros:3,apply_capable_macros:2,non_idempotent_retry_blocked:([.calls[]?|select(.idempotent==false and .retry_requested==true)]|length)}}' "$INPUT" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Reliability macros=\(.macros|length)"' "$OUT"; fi
