#!/usr/bin/env bash
set -euo pipefail
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
bash generators/cross_repo_impact.sh --input fixtures/federation/contract-propagation/input.json --output "$tmp/impact.json" --json >/dev/null
jq -e '.known_consumer_coverage==1 and (.consumers|length)==2 and (.generated_clients|length)==1 and .unknown_consumer_risk==false' "$tmp/impact.json" >/dev/null
bash generators/contract_propagation_plan.sh --input "$tmp/impact.json" --output "$tmp/plan.json" --json >/dev/null
jq -e '.summary.known_consumer_coverage==1 and .stages[0].id=="install-shim" and .stages[1].id=="migrate-consumers" and .stages[2].id=="remove-shim" and (.rollback_order==["remove-shim","migrate-consumers","install-shim"]) and .summary.out_of_order_breaking_rollouts==0' "$tmp/plan.json" >/dev/null
jq '.access.partial=true' fixtures/federation/contract-propagation/input.json > "$tmp/partial.json"
bash generators/cross_repo_impact.sh --input "$tmp/partial.json" --output "$tmp/partial-impact.json" --json >/dev/null
jq -e '.unknown_consumer_risk and .known_consumer_coverage==0' "$tmp/partial-impact.json" >/dev/null
echo "  [OK] cross-repo propagation coverage/shim order/partial risk"

