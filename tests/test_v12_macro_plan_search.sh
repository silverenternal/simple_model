#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
pass=0; fail=0; EXIT_CODE=0
check(){ local n="$1"; shift; if "$@" >/dev/null; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n"; fail=$((fail+1)); EXIT_CODE=1; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==============================================="
echo "  v1.2 macro plan search tests"
echo "==============================================="
check "macro plan search stable hash" bash -c "bash generators/macro_plan_search.sh --output '$tmp/search.json' --json | jq -e '.ok == true and (.stable_hash|length)==64 and .summary.selected >= 0'"
check "plugin macro-plan-search" bash -c "codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macro-plan-search --output '$tmp/plugin.json' --json | jq -e '.summary.stop_reason == \"budget_or_candidates_exhausted\"'"
echo "  passed: $pass"; echo "  failed: $fail"; exit $EXIT_CODE
