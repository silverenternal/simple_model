#!/usr/bin/env bash
set -euo pipefail
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
jq -n '{impact:"2 files",dynamic_risk:"low",macro_opportunities:["symbol.rename"],proof_status:"certified",selected_tests:[{id:"api",reason:"graph impact",graph_paths:["node:api->test"]}],artifacts:["generated/graph.json"],autofix_requested:true,macro_certificate:{trusted:true},repo_policy:{autofix:true},permissions:{write:true},base_fresh:true,event:"pull_request"}' > "$tmp/input.json"
bash tools/project_intelligence_pr_bot.sh --input "$tmp/input.json" --output "$tmp/a.json" --json >/dev/null
bash tools/project_intelligence_pr_bot.sh --input "$tmp/input.json" --output "$tmp/b.json" --json >/dev/null
cmp "$tmp/a.json" "$tmp/b.json"
jq -e '.marker=="<!-- simple-model-pr-intelligence -->" and .autofix.allowed and .duplicate_comments==0 and ((.evidence.selected_tests[0].graph_paths|length)==1)' "$tmp/a.json" >/dev/null
jq '.base_fresh=false' "$tmp/input.json" > "$tmp/stale.json"
bash tools/project_intelligence_pr_bot.sh --input "$tmp/stale.json" --output "$tmp/stale-report.json" --json >/dev/null
jq -e '.autofix.allowed==false and .autofix.reason=="stale base"' "$tmp/stale-report.json" >/dev/null
echo "  [OK] PR bot marker/stable evidence/autofix permission gates"
