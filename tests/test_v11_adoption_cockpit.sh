#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
pass=0; fail=0; EXIT_CODE=0
check(){ local name="$1"; shift; if "$@" >/dev/null; then echo "  [OK]   $name"; pass=$((pass+1)); else echo "  [FAIL] $name"; fail=$((fail+1)); EXIT_CODE=1; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==============================================="
echo "  v1.1 adoption cockpit tests"
echo "==============================================="
check "adoption cockpit artifacts" bash -c "bash generators/adoption_cockpit.sh --root . --struct ./struct.json --output-dir '$tmp/cockpit' --json | jq -e '.ok == true and .readiness.graph_confidence.nodes > 0' && test -f '$tmp/cockpit/cockpit.md' && test -f '$tmp/cockpit/cockpit.html'"
check "plugin adoption-cockpit command" bash -c "codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh adoption-cockpit --output-dir '$tmp/plugin-cockpit' --json | jq -e '.ok == true'"
echo "  passed: $pass"; echo "  failed: $fail"; exit $EXIT_CODE
