#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
pass=0; fail=0; EXIT_CODE=0
check(){ local name="$1"; shift; if "$@" >/dev/null; then echo "  [OK]   $name"; pass=$((pass+1)); else echo "  [FAIL] $name"; fail=$((fail+1)); EXIT_CODE=1; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==============================================="
echo "  v1.1 dynamic edge tests"
echo "==============================================="
check "dynamic edges trust states" bash -c "bash generators/dynamic_edge_resolver.sh --root . --struct ./struct.json --output '$tmp/dynamic.json' --json | jq -e '.schema_version==\"1.0\" and .summary.edges >= 0 and all(.edges[]?; .trust_state and .evidence_class and (.blocks_safe_apply|type)==\"boolean\")'"
check "dynamic edge spec" jq -e '(.edge_kinds|index("route_binding")) and (.trust_states|index("denied"))' specs/dynamic-edge.json
check "plugin dynamic-edges command" bash -c "codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh dynamic-edges --output '$tmp/plugin-dynamic.json' --json | jq -e '.ok == true'"
echo "  passed: $pass"; echo "  failed: $fail"; exit $EXIT_CODE
