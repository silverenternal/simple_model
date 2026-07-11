#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
pass=0; fail=0; EXIT_CODE=0
check(){ local name="$1"; shift; if "$@" >/dev/null; then echo "  [OK]   $name"; pass=$((pass+1)); else echo "  [FAIL] $name"; fail=$((fail+1)); EXIT_CODE=1; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==============================================="
echo "  v1.1 macro precondition tests"
echo "==============================================="
check "macro preconditions classify decisions" bash -c "bash generators/macro_preconditions.sh --root . --struct ./struct.json --output '$tmp/pre.json' --json | jq -e '.schema_version==\"1.0\" and .summary.macros >= 2 and all(.results[]; .decision)'"
check "macro contract v4 requires preconditions" jq -e '(.required|index("preconditions")) and (.required|index("affected_tests"))' macros/macro-contract-v4.schema.json
check "plugin macro-preconditions command" bash -c "codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macro-preconditions --output '$tmp/plugin-pre.json' --json | jq -e '.summary.macros >= 2'"
echo "  passed: $pass"; echo "  failed: $fail"; exit $EXIT_CODE
