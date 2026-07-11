#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0; EXIT_CODE=0
check(){ local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n"; fail=$((fail+1)); EXIT_CODE=1; fi; }
cd "$ROOT_DIR"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==============================================="
echo "  v1.0 production benchmark tests"
echo "==============================================="
check "production benchmark emits scorecard" bash -c "bash generators/production_benchmark.sh --root examples/plugin-target-repo --struct examples/plugin-target-repo/struct.json --output-dir '$tmp/bench' --json | jq -e '.ok == true and .metrics.parser_precision_proxy >= .thresholds.parser_precision_proxy'"
check "production benchmark artifact exists" test -s "$tmp/bench/production-scorecard.json"
echo "  passed: $pass"
echo "  failed: $fail"
exit $EXIT_CODE
