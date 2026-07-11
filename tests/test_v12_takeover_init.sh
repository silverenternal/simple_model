#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh --target-root . --struct ./struct.json takeover-init --output-dir "$tmp/adoption" --json > "$tmp/stdout.json"
jq -e '.ok==true and (.phases|length)>=8 and ([.phases[].order] == ([.phases[].order]|sort)) and all(.phases[];.owner=="macro" and .deterministic==true)' "$tmp/adoption/takeover-init.json" >/dev/null
jq -e 'has("blockers") and has("macro_safe_actions") and has("review_actions") and has("evidence_gaps") and has("next_commands")' "$tmp/adoption/takeover-init.json" >/dev/null
jq -e '.automation_model.macro_dominant==true and .automation_model.ai_may_apply_changes==false and .automation_model.ai_task_ratio<=.automation_model.ai_task_budget.max_ratio and (.ai_leaf_tasks|length)<=.automation_model.ai_task_budget.max_count and all(.ai_leaf_tasks[]?;.may_change_structure==false and (.output_schema|type)=="object")' "$tmp/adoption/takeover-init.json" >/dev/null
test -s "$tmp/adoption/takeover-init.md"
test -s "$tmp/adoption/interface-stability.json"
echo "v1.2 takeover init: ok"
