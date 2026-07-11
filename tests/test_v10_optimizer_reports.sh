#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0; EXIT_CODE=0
check(){ local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n"; fail=$((fail+1)); EXIT_CODE=1; fi; }
cd "$ROOT_DIR"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==============================================="
echo "  v1.0 optimizer report tests"
echo "==============================================="
bash generators/optimization_graph.sh --root . --struct ./struct.json --output "$tmp/graph.json" --json >/dev/null
bash generators/optimizer_search.sh --graph "$tmp/graph.json" --output "$tmp/search.json" --json >/dev/null
check "optimizer report emits json and markdown" bash -c "bash generators/optimizer_report.sh --graph '$tmp/graph.json' --search '$tmp/search.json' --output-dir '$tmp/report' --json | jq -e '.ok == true and .summary.selected >= 1 and (.review_checklist|length)>=4'"
check "optimizer report markdown exists" test -s "$tmp/report/optimizer-report.md"
check "optimizer review docs exist" grep -q "Simulate selected macros" docs/playbooks/optimizer-review.md
echo "  passed: $pass"
echo "  failed: $fail"
exit $EXIT_CODE
