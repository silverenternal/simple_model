#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0; EXIT_CODE=0
check(){ local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n"; fail=$((fail+1)); EXIT_CODE=1; fi; }
cd "$ROOT_DIR"
echo "==============================================="
echo "  v0.9 performance SLO tests"
echo "==============================================="

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

check "performance benchmark emits scorecard" bash generators/performance_benchmark.sh --root . --struct ./struct.json --output-dir "$tmp/perf" --jobs 2 --json
check "performance scorecard has budgets and hash" jq -e '.ok == true and (.summary.deterministic_hash|length)>0 and .budgets.fast_check_seconds >= 1' "$tmp/perf/scorecard.json"
check "performance dashboard renders html" bash generators/performance_dashboard.sh --scorecard "$tmp/perf/scorecard.json" --test-report "$tmp/perf/tests-warm/test-runner.json" --output "$tmp/perf/dashboard.html" --json
check "dashboard exists" test -s "$tmp/perf/dashboard.html"
check "release slo includes performance summary" bash -c "bash generators/release_slo.sh --performance '$tmp/perf/scorecard.json' --json | jq -e '.ok == true and (.performance_summary.deterministic_hash|length)>0'"
check "release docs mention performance budgets" grep -q "fast_check_seconds" docs/RELEASE_SLO.md
check "concurrency playbook exists" grep -q "simulation-only" docs/playbooks/concurrent-execution.md

echo "  passed: $pass"
echo "  failed: $fail"
exit $EXIT_CODE
