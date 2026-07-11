#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
pass=0; fail=0; EXIT_CODE=0
check(){ local n="$1"; shift; if "$@" >/dev/null; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n"; fail=$((fail+1)); EXIT_CODE=1; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==============================================="
echo "  v1.2 macro template synthesis tests"
echo "==============================================="
check "template synthesis review only" bash -c "bash generators/macro_template_synth.sh --output '$tmp/templates.json' --json | jq -e '.ok == true and .summary.templates >= 1 and all(.templates[]; .apply_capable == false and .promotion_criteria.false_safe_apply == 0)'"
check "template spec" jq -e '.promotion_policy == "review_only_until_proven"' specs/macro-template.json
check "plugin macro-templates" bash -c "codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macro-templates --output '$tmp/plugin.json' --json | jq -e '.summary.review_only >= 1'"
echo "  passed: $pass"; echo "  failed: $fail"; exit $EXIT_CODE
