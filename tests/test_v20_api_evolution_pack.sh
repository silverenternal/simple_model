#!/usr/bin/env bash
set -euo pipefail
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
jq -n '{consumers:[{id:"web",complete:false},{id:"worker",complete:false}]}' > "$tmp/input.json"
bash generators/api_migration_campaign.sh --input "$tmp/input.json" --output "$tmp/campaign.json" --json >/dev/null
jq -e '.summary.simulate_capable_macros==4 and .summary.apply_capable_macros==2 and .generated_clients_synchronized and (.compatibility_matrix|length)>=7 and (.consumer_ledger|length)==2' "$tmp/campaign.json" >/dev/null
echo "  [OK] API evolution compatibility matrix/consumer ledger"
