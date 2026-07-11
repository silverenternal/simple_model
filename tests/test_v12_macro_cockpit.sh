#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
pass=0; fail=0; EXIT_CODE=0
check(){ local n="$1"; shift; if "$@" >/dev/null; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n"; fail=$((fail+1)); EXIT_CODE=1; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==============================================="
echo "  v1.2 macro cockpit tests"
echo "==============================================="
check "macro cockpit artifacts" bash -c "bash generators/macro_cockpit.sh --output-dir '$tmp/cockpit' --json | jq -e '.ok == true and .summary.proof_bundle_hash != \"\"' && test -f '$tmp/cockpit/cockpit.md' && test -f '$tmp/cockpit/cockpit.html'"
check "plugin macro-cockpit" bash -c "codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macro-cockpit --output-dir '$tmp/plugin-cockpit' --json | jq -e '.summary.safe_plans >= 0'"
echo "  passed: $pass"; echo "  failed: $fail"; exit $EXIT_CODE
