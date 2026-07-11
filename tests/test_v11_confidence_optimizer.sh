#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
pass=0; fail=0; EXIT_CODE=0
check(){ local name="$1"; shift; if "$@" >/dev/null; then echo "  [OK]   $name"; pass=$((pass+1)); else echo "  [FAIL] $name"; fail=$((fail+1)); EXIT_CODE=1; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==============================================="
echo "  v1.1 confidence optimizer tests"
echo "==============================================="
check "confidence optimizer queues" bash -c "bash generators/confidence_optimizer.sh --root . --struct ./struct.json --output '$tmp/confidence.json' --json | jq -e '.ok == true and .policy.low_confidence_cannot_safe_apply == true and (.summary.recommendations >= 1)'"
check "plugin confidence-plan command" bash -c "codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh confidence-plan --output '$tmp/plugin-confidence.json' --json | jq -e '.ok == true'"
echo "  passed: $pass"; echo "  failed: $fail"; exit $EXIT_CODE
