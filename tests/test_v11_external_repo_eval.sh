#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
pass=0; fail=0; EXIT_CODE=0
check(){ local name="$1"; shift; if "$@" >/dev/null; then echo "  [OK]   $name"; pass=$((pass+1)); else echo "  [FAIL] $name"; fail=$((fail+1)); EXIT_CODE=1; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==============================================="
echo "  v1.1 external repo eval tests"
echo "==============================================="
check "external eval local only" bash -c "bash generators/external_repo_eval.sh --root . --struct ./struct.json --output '$tmp/eval.json' --redact-paths --json | jq -e '.ok == true and .safety.local_only == true and .safety.uploads == false and .summary.graph_nodes > 0'"
check "plugin external-eval command" bash -c "codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh external-eval --output '$tmp/plugin-eval.json' --json | jq -e '.ok == true'"
echo "  passed: $pass"; echo "  failed: $fail"; exit $EXIT_CODE
