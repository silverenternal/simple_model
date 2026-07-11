#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
pass=0; fail=0; EXIT_CODE=0
check(){ local name="$1"; shift; if "$@" >/dev/null; then echo "  [OK]   $name"; pass=$((pass+1)); else echo "  [FAIL] $name"; fail=$((fail+1)); EXIT_CODE=1; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==============================================="
echo "  v1.1 accuracy scorecard tests"
echo "==============================================="
check "accuracy scorecard fail-closed metrics" bash -c "bash generators/accuracy_scorecard.sh --output '$tmp/accuracy.json' --json | jq -e '.ok == true and .summary.symbol_recall_proxy >= .thresholds.symbol_recall_proxy and .summary.false_safe_apply == 0'"
check "plugin accuracy-scorecard command" bash -c "codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh accuracy-scorecard --output '$tmp/plugin-accuracy.json' --json | jq -e '.ok == true'"
echo "  passed: $pass"; echo "  failed: $fail"; exit $EXIT_CODE
