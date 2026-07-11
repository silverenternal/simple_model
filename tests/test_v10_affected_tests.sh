#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0; EXIT_CODE=0
check(){ local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n"; fail=$((fail+1)); EXIT_CODE=1; fi; }
cd "$ROOT_DIR"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==============================================="
echo "  v1.0 affected test precision tests"
echo "==============================================="
check "test impact dag includes semantic selectors" bash -c "bash generators/test_impact_dag.sh --root . --struct ./struct.json --output '$tmp/dag.json' --json | jq -e '.summary.semantic_nodes >= 1 and any(.tests[]; (.semantic_selectors|length) >= 1)'"
check "affected check remains bounded" bash -c "bash tools/test_runner.sh --mode affected --changed-files generators/semantic_graph.sh --output-dir '$tmp/tests' --cache '$tmp/cache.json' --json | jq -e '.summary.selected >= 1 and .summary.selected <= (.selected|length)'"
echo "  passed: $pass"
echo "  failed: $fail"
exit $EXIT_CODE
