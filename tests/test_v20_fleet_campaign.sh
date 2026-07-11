#!/usr/bin/env bash
set -euo pipefail
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
jq -n '{schema_version:"1.0",campaign_id:"upgrade-1",macro:"dependency.upgrade",repositories:[{id:"a"},{id:"b"},{id:"c"},{id:"d"}],cohorts:[{id:"0",repositories:["a","b"],canary:true},{id:"1",repositories:["c","d"],canary:false}],write_intent:false}' > "$tmp/input.json"
bash generators/fleet_campaign_plan.sh --input "$tmp/input.json" --output "$tmp/plan.json" --json >/dev/null
jq -e '.summary.read_only and .summary.repositories==4 and (.cohorts|length)==2 and .cohorts[0].canary' "$tmp/plan.json" >/dev/null
bash generators/fleet_campaign_execute.sh --plan "$tmp/plan.json" --output "$tmp/report.json" --json >/dev/null
jq -e '.status=="completed" and .resume_supported and .duplicate_prs==0 and .write_intent==false' "$tmp/report.json" >/dev/null
bash generators/fleet_campaign_execute.sh --plan "$tmp/plan.json" --output "$tmp/paused.json" --canary-failed --json >/dev/null
jq -e '.status=="paused" and .summary.canary_failed and .cohorts[1].status=="paused" and .cohorts[0].rollback=="rollback_canary"' "$tmp/paused.json" >/dev/null
echo "  [OK] fleet campaign read-only cohorts/canary pause/resume/idempotency"
