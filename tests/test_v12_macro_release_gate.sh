#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
pass=0; fail=0; EXIT_CODE=0
check(){ local n="$1"; shift; if "$@" >/dev/null; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n"; fail=$((fail+1)); EXIT_CODE=1; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==============================================="
echo "  v1.2 macro release gate tests"
echo "==============================================="
check "release slo v1.2 macro readiness" bash -c "bash generators/release_slo.sh --json > '$tmp/slo.json' && jq -e '.schema_version==\"2.2\" and .ok == true and .checks.macro_gauntlet == true and .checks.macro_proof_bundle == true and .checks.takeover_init == true and .checks.takeover_ai_budget == true and .checks.interface_stability == true and .checks.ai_tool_research == true and .v12_macro_readiness.proof_bundle.bundle_hash != \"\"' '$tmp/slo.json'"
check "release artifact is persisted" bash -c "jq -e '.ok==true and .v12_macro_readiness.competitive_research.summary.all_pains_mapped==true' generated/releases/v1.2-macro-readiness.json"
check "mcp exposes v1.2 product commands" bash -c "printf '{\"id\":1,\"method\":\"tools/list\"}\\n' | SIMPLE_MODEL_ROOT='$ROOT_DIR' bash tools/simple_model_mcp.sh | jq -e '([.result.tools[].name] | index(\"plugin_macro_cockpit\") != null and index(\"plugin_takeover_init\") != null and index(\"plugin_interface_stability\") != null and index(\"plugin_ai_tool_research\") != null)'"
echo "  passed: $pass"; echo "  failed: $fail"; exit $EXIT_CODE
