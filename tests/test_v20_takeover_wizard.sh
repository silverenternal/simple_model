#!/usr/bin/env bash
set -euo pipefail
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
jq -n '{project_id:"demo",interfaces:[{id:"api",blocked:true,evidence:["parser","owner"]},{id:"dynamic",blocked:true,evidence:["runtime"]},{id:"ok",blocked:false,evidence:["contract"]}]}' > "$tmp/input.json"
bash generators/takeover_wizard.sh --input "$tmp/input.json" --output-dir "$tmp/session" --json >/dev/null
jq -e '.status=="planned" and .non_destructive and (.writes|length)==4 and .macro_plan.mode=="review_only" and .ai_task_ratio<=0.10' "$tmp/session/session.json" >/dev/null
bash generators/takeover_wizard.sh --input "$tmp/input.json" --output-dir "$tmp/session" --resume --json >/dev/null
jq -e '.status=="resumed"' "$tmp/session/session.json" >/dev/null
bash generators/interface_unblock.sh --input "$tmp/input.json" --output "$tmp/unblock.json" --json >/dev/null
jq -e '.summary.interface_blocked_ratio<0.10 and .summary.ai_task_ratio<=0.10' "$tmp/unblock.json" >/dev/null
echo "  [OK] takeover wizard resumable/non-destructive interface blocked<0.10"
