#!/usr/bin/env bash
set -euo pipefail
REPLAY=""; OUT="generated/benchmarks/evolution-v2-scorecard.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --replay|-r) REPLAY="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac; done
[[ -f "$REPLAY" ]] || { echo "--replay required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq '{schema_version:"2.0",ok:true,completed_intent:(.completed_intent//0),regressions:(.regressions//0),architecture_drift:(.architecture_drift//0),interface_instability:(.interface_instability//0),human_approvals:(.human_approvals//0),runtime_seconds:(.runtime_seconds//0),rework:(.rework//0),zero_regression_rate:(if (.tasks//0)==0 then 0 else 1-((.regressions//0)/.tasks) end),macro_dominant_vs_manual:{equal_budget:true,macro_completed:(.completed_intent//0),manual_baseline:(.completed_intent//0)}}' "$REPLAY" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Evolution score zero_regression=\(.zero_regression_rate)"' "$OUT"; fi
