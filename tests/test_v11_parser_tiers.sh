#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
pass=0; fail=0; EXIT_CODE=0
check(){ local name="$1"; shift; if "$@" >/dev/null; then echo "  [OK]   $name"; pass=$((pass+1)); else echo "  [FAIL] $name"; fail=$((fail+1)); EXIT_CODE=1; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==============================================="
echo "  v1.1 parser tier tests"
echo "==============================================="
check "parser tier registry emits coverage" bash -c "bash generators/parser_tier_registry.sh --root . --output '$tmp/tiers.json' --json | jq -e '.schema_version==\"1.0\" and .summary.files > 0 and .release_gate.fail_closed == true'"
check "parser tier spec has fail closed policy" jq -e '.release_gate.fail_on_low_confidence_safe_apply == true' specs/parser-tier-registry.json
check "plugin parser-tiers command" bash -c "codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh parser-tiers --output '$tmp/plugin-tiers.json' --json | jq -e '.summary.files > 0'"
echo "  passed: $pass"; echo "  failed: $fail"; exit $EXIT_CODE
