#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh --target-root . --struct ./struct.json interface-stability --output "$tmp/stability.json" --json > "$tmp/stdout.json"
jq -e '.ok==true and (.summary.interfaces>0) and ([.interfaces[].status]|all(.=="stable" or .=="provisional" or .=="experimental" or .=="deprecated" or .=="blocked"))' "$tmp/stability.json" >/dev/null
jq -e 'all(.interfaces[]; (.breaking_change_policy|length)>0 and (.compatibility_window.minimum|length)>0 and has("affected_tests") and has("macro_recommendations"))' "$tmp/stability.json" >/dev/null
jq -e '.automation_model.macro_dominant==true and .automation_model.ai_may_apply_changes==false and all(.ai_leaf_tasks[]?;.may_change_structure==false)' "$tmp/stability.json" >/dev/null
test -s "${tmp}/stability.md"
echo "v1.2 interface stability commitment: ok"
