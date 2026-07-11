#!/usr/bin/env bash
set -euo pipefail
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
jq -n '{queries:[{query:"find api",plan_hash:"abc",graph_paths:["node:api->node:test"],evidence:["ledger:1"],command:"mql_plan --query q.json"}],dirty_worktree:false,certified:true,artifacts:["generated/graph.json"]}' > "$tmp/input.json"
bash generators/intelligence_cockpit_v3.sh --input "$tmp/input.json" --output "$tmp/session.json" --json >/dev/null
jq -e '.terminal_feature_parity==1 and .unreplayable_answers==0 and .handoff.replayable and .policy.simulation_allowed and (.queries[0].graph_paths|length)==1' "$tmp/session.json" >/dev/null
bash tools/mql_repl.sh --session "$tmp/session.json" --output "$tmp/repl.json" --json >/dev/null
jq -e '.ok and .handoff.replayable and (.answers|length)==1' "$tmp/repl.json" >/dev/null
jq '.dirty_worktree=true' "$tmp/input.json" > "$tmp/dirty.json"
bash generators/intelligence_cockpit_v3.sh --input "$tmp/dirty.json" --output "$tmp/dirty-session.json" --json >/dev/null
jq -e '.policy.simulation_allowed==false and .policy.dirty_worktree_gate' "$tmp/dirty-session.json" >/dev/null
echo "  [OK] interactive cockpit replayable answers/terminal parity/policy gates"

