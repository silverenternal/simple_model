#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh ai-tool-research --output "$tmp/research.json" --json > "$tmp/stdout.json"
jq -e '.ok==true and .summary.tools>=6 and .summary.sources>=10 and .summary.pain_points>=6 and .summary.macro_wisdom_bets>=6' "$tmp/research.json" >/dev/null
jq -e '.summary.all_pains_mapped==true and .summary.all_sources_linked==true and all(.pain_points[];(.evidence|length)>0 and (.deterministic_artifacts|length)>0)' "$tmp/research.json" >/dev/null
jq -e '.automation_model.macro_dominant==true and .automation_model.ai_decides_structure==false and .automation_model.ai_may_promote_or_apply_macros==false' "$tmp/research.json" >/dev/null
test -s "$tmp/research.md"
echo "v1.2 AI tool pain research: ok"
