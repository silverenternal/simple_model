#!/usr/bin/env bash
set -euo pipefail
INPUT=""; OUT="generated/performance/v2-scorecard.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --benchmark|-b) INPUT="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
[[ -f "$INPUT" ]] || { echo "--benchmark required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq '{schema_version:"2.0",ok:(.summary.missed_affected_tests==0 and .summary.duplicate_heavy_phase_executions==0),
  suites:{contract:{label:"contract",route:"affected",heavy:false},integration:{label:"integration",route:"affected",heavy:false},benchmark:{label:"benchmark",route:"full",heavy:true},release:{label:"release",route:"full-cache-disabled",heavy:true}},
  saved_time_seconds:((.scenarios|map(.affected_check_p95_seconds)|add) / 2),
  cache_trust:(.scenarios|map({scenario:.name,trust:.cache_trust})),
  missed_test_audit:{missed:(.summary.missed_affected_tests),escalations:["cache_corruption"]},
  heavy_phase_accounting:.heavy_phases,
  budgets:{incremental_analysis_p95_seconds:2,affected_check_p95_seconds:30,unlabeled_suite_max_seconds:30}}' "$INPUT" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Test economics saved=\(.saved_time_seconds)s duplicate_heavy=\(.heavy_phase_accounting.duplicate_executions)"' "$OUT"; fi
