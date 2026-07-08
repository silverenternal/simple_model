#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"; rm -rf "$ROOT_DIR/dist"' EXIT
pass=0; fail=0; EXIT_CODE=0
check(){ local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n"; fail=$((fail+1)); EXIT_CODE=1; fi; }

WRAP="$ROOT_DIR/plugins/simple-model-project-intelligence/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh"
SRC_WRAP="$ROOT_DIR/codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh"
TARGET="$ROOT_DIR/examples/plugin-target-repo"

cd "$ROOT_DIR"
check "marketplace json" jq -e '.name=="simple-model" and .plugins[0].name=="simple-model-project-intelligence"' .agents/plugins/marketplace.json
check "plugin manifest json" jq -e '.name=="simple-model-project-intelligence" and .version=="0.6.0" and .skills=="./skills/"' plugins/simple-model-project-intelligence/.codex-plugin/plugin.json
check "skill frontmatter has name" grep -q '^name: simple-model-project-intelligence$' codex/skills/simple-model-project-intelligence/SKILL.md
check "skill openai yaml parseable-ish" grep -q 'display_name: "Simple Model Project Intelligence"' codex/skills/simple-model-project-intelligence/agents/openai.yaml
check "no plugin TODO placeholders" bash -c "! rg -n 'TODO|\\[TODO|placeholder' codex/skills/simple-model-project-intelligence plugins/simple-model-project-intelligence .agents/plugins"
check "source and plugin skill sync" bash tools/sync_codex_plugin.sh --check
check "wrapper help" "$WRAP" help
check "source wrapper commands json" bash -c "'$SRC_WRAP' commands --json | jq -e '.commands|length >= 10'"
check "plugin wrapper commands json" bash -c "'$WRAP' commands --json | jq -e '.commands[]|select(.name==\"doctor\")'"
check "doctor json" bash -c "'$WRAP' --target-root '$TARGET' doctor --json | jq -e '.ok == true and .checks.jq == true'"
check "cross repo doctor with SIMPLE_MODEL_HOME" bash -c "cd '$TMP_DIR' && SIMPLE_MODEL_HOME='$ROOT_DIR' '$WRAP' --target-root '$TARGET' doctor --json | jq -e '.simple_model_home == \"$ROOT_DIR\"'"
check "cross repo interface scan" bash -c "cd '$TMP_DIR' && SIMPLE_MODEL_HOME='$ROOT_DIR' '$WRAP' --target-root '$TARGET' --struct '$TARGET/struct.json' interfaces | jq -e '.components[0].component == \"Server\"'"
check "plugin demo" bash -c "bash examples/plugin-demo/run.sh | jq -e '.ok == true'"
check "package plugin" bash -c "bash tools/package_codex_plugin.sh --version 0.6.0 | jq -e '.ok == true and .sha256'"
check "package zip exists" test -s dist/simple-model-project-intelligence-plugin-0.6.0.zip
check "plugin docs mention update" grep -q 'Update Or Remove' docs/CODEX_PLUGIN.md
check "plugin workflow exists" test -f .github/workflows/plugin.yml
check "mcp plugin tools list" bash -c "printf '{\"id\":1,\"method\":\"tools/list\"}\\n' | SIMPLE_MODEL_ROOT='$ROOT_DIR' bash tools/simple_model_mcp.sh | jq -e '.result.tools[]|select(.name==\"plugin_doctor\")'"
check "mcp plugin doctor call" bash -c "printf '{\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"plugin_doctor\",\"arguments\":{\"target_root\":\"$TARGET\"}}}\\n' | SIMPLE_MODEL_ROOT='$ROOT_DIR' bash tools/simple_model_mcp.sh | jq -e '.result.ok == true'"
check "todo done count" bash -c "jq -e '[.todos[]|select(.status==\"done\")]|length == 12' todo.json"

echo "  passed: $pass"
echo "  failed: $fail"
exit $EXIT_CODE
