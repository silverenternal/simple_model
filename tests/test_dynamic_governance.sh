#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
pass=0; fail=0; EXIT_CODE=0
check(){ local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n"; fail=$((fail+1)); EXIT_CODE=1; fi; }

cd "$ROOT_DIR"
TARGET="$ROOT_DIR/examples/dynamic-case-study/target"
STRUCT="$TARGET/struct.json"
WRAP="$ROOT_DIR/codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh"

check "dynamic surface schema" jq -e '.properties.nodes.items.required|index("risk_level")' specs/dynamic-surface-ir.json
check "runtime observation schema" jq -e '.properties.observations.items.required|index("kind")' specs/runtime-observation.schema.json
check "framework resolvers detect dynamic surfaces" bash -c "bash generators/dynamic_framework_resolvers.sh --root '$TARGET' --struct '$STRUCT' --json | jq -e '.summary.routes >= 2 and .summary.di_bindings >= 1 and .summary.event_subscriptions >= 1 and .summary.plugin_registrations >= 1'"
check "dynamic scan detects env generated unsafe" bash -c "bash generators/dynamic_surface_scan.sh --root '$TARGET' --struct '$STRUCT' --output '$TMP_DIR/dynamic.json' --json | jq -e '.summary.nodes >= 8 and .summary.env_keys >= 2 and .summary.generated_files >= 1 and .summary.dynamic_unsafe >= 1'"
check "dynamic nodes carry evidence" bash -c "jq -e 'all(.nodes[]; .id and .evidence and .confidence and .resolver and .verification_status)' '$TMP_DIR/dynamic.json'"
check "semantic ir keeps dynamic separate" bash -c "bash generators/semantic_interface_ir.sh --root '$TARGET' --struct '$STRUCT' --output '$TMP_DIR/ir.json' --json | jq -e '.schema_version == \"2.0\" and .summary.dynamic_surfaces >= 1 and .dynamic_surfaces.summary.dynamic_unsafe >= 1 and (.nodes|type)==\"array\"'"
check "project structure generated provenance" bash -c "bash generators/project_structure_miner.sh --root '$TARGET' --struct '$STRUCT' --output '$TMP_DIR/project.json' --json | jq -e '.summary.generated >= 1'"
check "pr gate includes dynamic section" bash -c "(bash generators/pr_gate.sh --root '$TARGET' --struct '$STRUCT' --files 'src/plugins.ts' --json || true) | jq -e '(.dynamic.affected|length) >= 1 and (.dynamic.dynamic_unsafe|length) >= 1'"
check "plugin dynamic-surface command" bash -c "'$WRAP' --target-root '$TARGET' --struct '$STRUCT' dynamic-surface --output '$TMP_DIR/wrap-dynamic.json' --json | jq -e '.summary.nodes >= 8'"
check "mcp exposes dynamic surface" bash -c "printf '{\"id\":1,\"method\":\"tools/list\"}\\n' | SIMPLE_MODEL_ROOT='$ROOT_DIR' bash tools/simple_model_mcp.sh | jq -e '.result.tools[]|select(.name==\"plugin_dynamic_surface\")'"

echo "  passed: $pass"
echo "  failed: $fail"
exit $EXIT_CODE
