#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0; EXIT_CODE=0
check(){ local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n"; fail=$((fail+1)); EXIT_CODE=1; fi; }
cd "$ROOT_DIR"
echo "==============================================="
echo "  v0.9 test acceleration tests"
echo "==============================================="

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

check "test impact dag emits domains" bash generators/test_impact_dag.sh --root . --struct ./struct.json --output "$tmp/dag.json" --json
check "test dag supports fast plugin dynamic benchmark full" jq -e '.ok == true and .summary.tests > 0 and (.selection_rules.fast|index("adoption")) != null and (.selection_rules.full|length) >= 5' "$tmp/dag.json"

check "smart test runner fast mode passes" bash tools/test_runner.sh --mode fast --jobs 2 --cache "$tmp/cache.json" --output-dir "$tmp/tests1" --json
check "fast runner is bounded and conflict-aware" jq -e '.ok == true and .summary.selected == 2 and .summary.failed == 0 and .scheduler.effective_jobs == 1' "$tmp/tests1/test-runner.json"

check "smart test runner cache warm pass" bash tools/test_runner.sh --mode fast --jobs 2 --cache "$tmp/cache.json" --output-dir "$tmp/tests2" --json
check "cache stores content-addressed results" jq -e '.ok == true and .summary.cached >= 1 and all(.results[]; has("stdout_digest") and has("stderr_digest"))' "$tmp/tests2/test-runner.json"

check "cache lookup returns stable key" bash generators/test_cache.sh --cache "$tmp/cache.json" --root . --command "bash tests/test_v04_roadmap.sh" --inputs "todo.json,tests/test_v04_roadmap.sh" --lookup --json

echo "  passed: $pass"
echo "  failed: $fail"
exit $EXIT_CODE
