#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
pass=0; fail=0; EXIT_CODE=0
check(){ local name="$1"; shift; if "$@" >/dev/null; then echo "  [OK]   $name"; pass=$((pass+1)); else echo "  [FAIL] $name"; fail=$((fail+1)); EXIT_CODE=1; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==============================================="
echo "  v1.1 release gate tests"
echo "==============================================="
check "release slo v1.1 artifacts" bash -c "bash generators/release_slo.sh --json > '$tmp/slo.json' && jq -e '(.schema_version==\"2.1\" or .schema_version==\"2.2\") and .ok == true and .checks.macro_contract_v4 == true and .checks.accuracy_scorecard == true and .v11_readiness.parser_tiers.files > 0' '$tmp/slo.json'"
check "mcp exposes v11 command" bash -c "printf '{\"id\":1,\"method\":\"tools/list\"}\\n' | SIMPLE_MODEL_ROOT='$ROOT_DIR' bash tools/simple_model_mcp.sh | jq -e '.result.tools[]|select(.name==\"plugin_adoption_cockpit\")'"
echo "  passed: $pass"; echo "  failed: $fail"; exit $EXIT_CODE
