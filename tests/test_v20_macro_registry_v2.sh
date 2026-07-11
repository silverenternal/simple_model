#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(pwd)"; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
jq -n '{schema_version:"2.0",policy:{min_external_repositories:2},macros:[
{id:"base",version:"1.0.0",dependencies:[],status:"active",certificate:{trusted:true,hash:"a"},external_repositories:["repo-a","repo-b"]},
{id:"child",version:"1.0.0",dependencies:["base"],status:"active",certificate:{trusted:true,hash:"b"},external_repositories:["repo-a","repo-b"]},
{id:"narrow",version:"1.0.0",dependencies:["base"],status:"active",certificate:{trusted:true,hash:"c"},external_repositories:["repo-a"]}
]}' > "$tmp/input.json"
bash generators/macro_registry_v2.sh --input "$tmp/input.json" --output "$tmp/registry.json" --json >/dev/null
jq -e '.ok and .resolution_order==["base","child","narrow"] and .summary.apply_eligible==2 and any(.macros[];.id=="narrow" and .apply_eligible==false)' "$tmp/registry.json" >/dev/null
bash generators/macro_resolve.sh --registry "$tmp/registry.json" --macro-id child --output "$tmp/resolve.json" --json >/dev/null
jq -e '.ok and .apply_allowed and (.resolution_order|index("base")<index("child"))' "$tmp/resolve.json" >/dev/null
bash generators/macro_revoke.sh --registry "$tmp/registry.json" --macro-id child --reason "bad proof" --output "$tmp/revoked.json" >/dev/null
jq -e 'any(.macros[];.id=="child" and .status=="revoked" and .apply_eligible==false) and any(.revocations[];.macro_id=="child" and .audit_preserved)' "$tmp/revoked.json" >/dev/null
jq -n '{schema_version:"2.0",macros:[{id:"a",dependencies:["b"],certificate:{trusted:true}},{id:"b",dependencies:["a"],certificate:{trusted:true}}]}' > "$tmp/cycle.json"
if bash generators/macro_registry_v2.sh --input "$tmp/cycle.json" --output "$tmp/cycle-report.json" --json >/dev/null; then exit 1; fi
jq -e '.ok==false and .summary.cycles==1' "$tmp/cycle-report.json" >/dev/null
echo "  [OK] registry deterministic deps/diversity/revocation/audit"
