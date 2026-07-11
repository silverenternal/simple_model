#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
pass=0; fail=0; EXIT_CODE=0
check(){ local n="$1"; shift; if "$@" >/dev/null; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n"; fail=$((fail+1)); EXIT_CODE=1; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==============================================="
echo "  v1.2 macro operator IR tests"
echo "==============================================="
check "operator ir normalizes macros" bash -c "bash generators/macro_operator_ir.sh --output '$tmp/operators.json' --json | jq -e '.ok == true and .summary.operators > 0 and all(.operators[]; .input_selectors and .graph_effects and .write_effects and .rollback_scope)'"
check "operator ir spec" jq -e '.validation.require_typed_selectors == true and (.required|index("score_factors"))' specs/macro-operator-ir.json
check "plugin macro-operator-ir" bash -c "codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macro-operator-ir --output '$tmp/plugin.json' --json | jq -e '.summary.operators > 0'"
echo "  passed: $pass"; echo "  failed: $fail"; exit $EXIT_CODE
