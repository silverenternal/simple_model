#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
pass=0; fail=0; EXIT_CODE=0
check(){ local n="$1"; shift; if "$@" >/dev/null; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n"; fail=$((fail+1)); EXIT_CODE=1; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==============================================="
echo "  v1.2 macro gauntlet tests"
echo "==============================================="
check "macro gauntlet scorecard" bash -c "bash generators/macro_gauntlet.sh --output '$tmp/gauntlet.json' --json | jq -e '.ok == true and .summary.false_safe_apply == 0 and .summary.transaction_rollback_success >= .thresholds.rollback_success'"
check "macro gauntlet cases" jq -e '(.cases|length >= 4) and (.thresholds.false_safe_apply == 0)' benchmarks/macro-gauntlet/cases.json
check "plugin macro-gauntlet" bash -c "codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macro-gauntlet --output '$tmp/plugin.json' --json | jq -e '.ok == true'"
echo "  passed: $pass"; echo "  failed: $fail"; exit $EXIT_CODE
