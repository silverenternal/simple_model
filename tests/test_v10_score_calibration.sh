#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0; EXIT_CODE=0
check(){ local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n"; fail=$((fail+1)); EXIT_CODE=1; fi; }
cd "$ROOT_DIR"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==============================================="
echo "  v1.0 score calibration tests"
echo "==============================================="
check "score model schema" jq -e '(.required|index("weights")) and (.required|index("evidence"))' specs/score-model.json
check "score calibration emits deterministic model" bash -c "bash generators/score_calibrate.sh --corpus '$tmp/corpus' --output '$tmp/model.json' --json | jq -e '.ok == true and .validation.ok == true and .evidence.cases >= 3'"
check "optimizer search still works with graph" bash -c "bash generators/optimization_graph.sh --root examples/plugin-target-repo --struct examples/plugin-target-repo/struct.json --output '$tmp/graph.json' --json >/dev/null && bash generators/optimizer_search.sh --graph '$tmp/graph.json' --output '$tmp/search.json' --json | jq -e '.ok == true and (.decision_trace|type)==\"array\"'"
echo "  passed: $pass"
echo "  failed: $fail"
exit $EXIT_CODE
