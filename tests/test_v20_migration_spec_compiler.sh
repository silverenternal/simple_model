#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(pwd)"; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
jq -n '{schema_version:"1.0",before:{"/health":{method:"GET"},legacy:{field:"old"},data_schema:{version:1}},after:{"/health":{method:"GET"},new_endpoint:{method:"GET"},legacy:null,data_schema:{version:2}},producers:["api-service"],consumers:[{id:"web",planned:true},{id:"worker",planned:true}],graph_edges:[{from:"api-service",to:"web",kind:"contract"}]}' > "$tmp/input.json"
jq '.before' "$tmp/input.json" > "$tmp/before.json"
jq '.after' "$tmp/input.json" > "$tmp/after.json"
bash generators/contract_diff_v2.sh --before "$tmp/before.json" --after "$tmp/after.json" --output "$tmp/diff.json" --json >/dev/null
jq -e '.summary.compatible_additions==1 and .summary.breaking>=1 and .summary.data_migrations==1' "$tmp/diff.json" >/dev/null
bash generators/migration_spec_compile.sh --input "$tmp/input.json" --output "$tmp/plan.json" --json >/dev/null
jq -e '.ok and .summary.breaking_change_detection_rate==1 and .summary.unplanned_impacted_consumers==0 and .summary.irreversible_data_changes==1 and any(.stages[];.id=="data-migration" and .backup_required and .validation_required) and (.rollback_order == (.stages|map(.id)|reverse)) and (.links.unified_graph_edges|length)==1' "$tmp/plan.json" >/dev/null
jq -e '.status=="review_only" and (.required_approval|index("breaking_changes"))' macros/packs/contract-migrations/pack.json >/dev/null
echo "  [OK] migration compiler staged rollback/backup/consumer links"
