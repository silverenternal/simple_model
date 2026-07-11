#!/usr/bin/env bash
set -euo pipefail
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
bash generators/macro_gauntlet_v2.sh --cases benchmarks/macro-gauntlet-v2/cases.json --output "$tmp/report.json" --json >/dev/null
jq -e '.summary.cases==500 and .summary.held_out==100 and .summary.false_safe_apply==0 and .summary.rollback_success==1 and .summary.replay_determinism==1 and .summary.precision>=0.99 and .summary.recall>=0.97 and (.summary.confidence_intervals.precision|length)==2' "$tmp/report.json" >/dev/null
jq -e '(.cases|length)==500 and ([.cases[].kind]|unique|length)==8 and .thresholds.false_safe_apply==0' benchmarks/macro-gauntlet-v2/cases.json >/dev/null
echo "  [OK] macro gauntlet cases=500 false_safe_apply=0 held_out=100"
