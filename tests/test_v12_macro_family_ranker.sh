#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
pass=0; fail=0; EXIT_CODE=0
check(){ local n="$1"; shift; if "$@" >/dev/null; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n"; fail=$((fail+1)); EXIT_CODE=1; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==============================================="
echo "  v1.2 macro family ranker tests"
echo "==============================================="
check "family ranker scores" bash -c "bash generators/macro_family_ranker.sh --output '$tmp/rank.json' --json | jq -e '.ok == true and all(.families[]; has(\"value_score\") and has(\"safety_score\") and has(\"promotion_score\"))'"
check "plugin macro-family-ranker" bash -c "codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macro-family-ranker --output '$tmp/plugin.json' --json | jq -e '.summary.families >= 0'"
echo "  passed: $pass"; echo "  failed: $fail"; exit $EXIT_CODE
