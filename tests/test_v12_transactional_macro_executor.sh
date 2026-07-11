#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
pass=0; fail=0; EXIT_CODE=0
check(){ local n="$1"; shift; if "$@" >/dev/null; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n"; fail=$((fail+1)); EXIT_CODE=1; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==============================================="
echo "  v1.2 macro transaction tests"
echo "==============================================="
bash generators/macro_plan_search.sh --output "$tmp/search.json" --json >/dev/null
check "macro transaction simulate" bash -c "bash generators/macro_transaction.sh --plan '$tmp/search.json' --output '$tmp/tx.json' --json | jq -e '.transaction.workspace_isolation == true and .summary.rollback_ready == true and .summary.resumable == true'"
check "plugin macro-transaction" bash -c "codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macro-transaction --output '$tmp/plugin.json' --json | jq -e '.summary.rollback_ready == true'"
echo "  passed: $pass"; echo "  failed: $fail"; exit $EXIT_CODE
