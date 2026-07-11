#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
pass=0; fail=0; EXIT_CODE=0
check(){ local name="$1"; shift; if "$@" >/dev/null; then echo "  [OK]   $name"; pass=$((pass+1)); else echo "  [FAIL] $name"; fail=$((fail+1)); EXIT_CODE=1; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==============================================="
echo "  v1.1 macro generation tests"
echo "==============================================="
check "macro candidates are review only" bash -c "bash generators/macro_generate_from_findings.sh --output '$tmp/candidates.json' --json | jq -e '.summary.candidates >= 1 and .summary.apply_capable == 0 and all(.candidates[]; .status==\"review_only\" and .apply_capable == false)'"
check "plugin macro-generate command" bash -c "codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macro-generate --output '$tmp/plugin-candidates.json' --json | jq -e '.summary.candidates >= 1'"
echo "  passed: $pass"; echo "  failed: $fail"; exit $EXIT_CODE
