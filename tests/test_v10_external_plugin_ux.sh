#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0; EXIT_CODE=0
check(){ local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n"; fail=$((fail+1)); EXIT_CODE=1; fi; }
cd "$ROOT_DIR"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
WRAP="$ROOT_DIR/codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh"
echo "==============================================="
echo "  v1.0 external plugin UX tests"
echo "==============================================="
check "adopt command external repo flow" bash -c "'$WRAP' --target-root examples/plugin-target-repo --struct examples/plugin-target-repo/struct.json adopt --output-dir '$tmp/adopt' --json | jq -e '.ok == true and .phases.semantic_graph.nodes >= 1'"
check "plugin v10 commands listed" bash -c "'$WRAP' commands --json | jq -e '(.commands[]|select(.name==\"adopt\")) and (.commands[]|select(.name==\"semantic-graph\"))'"
check "docs mention production optimizer flow" grep -q "Production Optimizer Flow" README.md
check "mcp exposes adopt" bash -c "printf '{\"id\":1,\"method\":\"tools/list\"}\\n' | SIMPLE_MODEL_ROOT='$ROOT_DIR' bash tools/simple_model_mcp.sh | jq -e '.result.tools[]|select(.name==\"plugin_adopt\")'"
echo "  passed: $pass"
echo "  failed: $fail"
exit $EXIT_CODE
