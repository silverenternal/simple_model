#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0; EXIT_CODE=0
check(){ local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n"; fail=$((fail+1)); EXIT_CODE=1; fi; }
cd "$ROOT_DIR"
echo "==============================================="
echo "  v0.9 plugin acceleration tests"
echo "==============================================="

WRAP="$ROOT_DIR/codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

check "command manifest exposes v09 commands" jq -e '(.commands[]|select(.name=="fast-check")) and (.commands[]|select(.name=="performance-benchmark")) and all(.commands[]; ((.tests // [])|length)>0 and has("release_gate"))' codex/skills/simple-model-project-intelligence/references/command-manifest.json
check "plugin fast-check command" bash -c "'$WRAP' fast-check --jobs 2 --output-dir '$tmp/fast' --json | jq -e '.ok == true and .summary.selected == 2'"
check "plugin test-plan command" bash -c "'$WRAP' test-plan --output '$tmp/dag.json' --json | jq -e '.summary.tests > 0'"
check "plugin optimization graph command" bash -c "'$WRAP' optimization-graph --output '$tmp/graph.json' --json | jq -e '(.graph_hash|length)==64'"
check "mcp exposes acceleration commands" bash -c "printf '{\"id\":1,\"method\":\"tools/list\"}\\n' | SIMPLE_MODEL_ROOT='$ROOT_DIR' bash tools/simple_model_mcp.sh | jq -e '.result.tools[]|select(.name==\"plugin_fast_check\")'"

echo "  passed: $pass"
echo "  failed: $fail"
exit $EXIT_CODE
