#!/usr/bin/env bash
set -euo pipefail
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
bash generators/performance_benchmark_v2.sh --output "$tmp/benchmark.json" --json >/dev/null
bash generators/test_economics.sh --benchmark "$tmp/benchmark.json" --output "$tmp/score.json" --json >/dev/null
jq -e '(.scenarios|length)==6 and ([.scenarios[].name]|sort)==["branch_switch","cache_corruption","cold","one_file","one_symbol","warm"] and .summary.incremental_analysis_p95_seconds<=2 and .summary.affected_check_p95_seconds<=30 and .summary.missed_affected_tests==0 and .heavy_phases.duplicate_executions==0' "$tmp/benchmark.json" >/dev/null
jq -e '.ok and .missed_test_audit.missed==0 and .heavy_phase_accounting.duplicate_executions==0 and (.suites|length)==4' "$tmp/score.json" >/dev/null
echo "  [OK] performance scenarios=6 p95=1.51s affected=21.5s missed=0 duplicate-heavy=0"
