#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
pass=0; fail=0; EXIT_CODE=0
check(){ local n="$1"; shift; if "$@" >/dev/null; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n"; fail=$((fail+1)); EXIT_CODE=1; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==============================================="
echo "  v1.2 macro advisor tests"
echo "==============================================="
check "macro advisor lists actions" bash -c "bash generators/macro_advisor.sh --root . --struct ./struct.json --output '$tmp/advisor.json' --json | jq -e '.ok == true and .policy.dirty_worktree_blocks_apply == true and (.lists|has(\"safe_now\") and has(\"gather_evidence\"))'"
check "plugin macro-advisor" bash -c "codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macro-advisor --output '$tmp/plugin.json' --json | jq -e '.ok == true'"
echo "  passed: $pass"; echo "  failed: $fail"; exit $EXIT_CODE
