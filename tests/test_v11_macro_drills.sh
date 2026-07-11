#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
pass=0; fail=0; EXIT_CODE=0
check(){ local name="$1"; shift; if "$@" >/dev/null; then echo "  [OK]   $name"; pass=$((pass+1)); else echo "  [FAIL] $name"; fail=$((fail+1)); EXIT_CODE=1; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==============================================="
echo "  v1.1 macro drill tests"
echo "==============================================="
check "macro drill idempotency rollback" bash -c "bash generators/macro_drill.sh --root . --output '$tmp/drill.json' --json | jq -e '.ok == true and .summary.idempotent == true and .summary.rollback_ok == true'"
check "plugin macro-drill command" bash -c "codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macro-drill --output '$tmp/plugin-drill.json' --json | jq -e '.ok == true'"
echo "  passed: $pass"; echo "  failed: $fail"; exit $EXIT_CODE
