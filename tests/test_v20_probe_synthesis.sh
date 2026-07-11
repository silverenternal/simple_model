#!/usr/bin/env bash
set -euo pipefail
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
jq -n '{obligations:[{id:"edge-1",evidence_node:"node-1",discharged:true},{id:"edge-2",evidence_node:"node-2",discharged:true},{id:"edge-3",evidence_node:"node-3",discharged:false}],budget:{max_probes:3,timeout_ms:1000,network_allowlist:[]}}' > "$tmp/input.json"
bash generators/probe_synthesize.sh --input "$tmp/input.json" --output "$tmp/plan.json" --json >/dev/null
jq -e '.summary.probes==3 and .summary.blocker_discharge_rate>=0.60 and all(.probes[];.read_only and .network==false and (.argv|type)=="array")' "$tmp/plan.json" >/dev/null
bash generators/probe_budget.sh --plan "$tmp/plan.json" --output "$tmp/budget.json" --json >/dev/null
jq -e '.ok and .decision=="allow" and .unsafe_probe_executions==0' "$tmp/budget.json" >/dev/null
jq '.probes[0].argv=["git","status;rm","--short"]' "$tmp/plan.json" > "$tmp/unsafe.json"
if bash generators/probe_budget.sh --plan "$tmp/unsafe.json" --output "$tmp/unsafe-report.json" --json >/dev/null 2>&1; then exit 1; fi
jq -e '.ok==false and .error.code=="unsafe_probe" and .fail_closed' "$tmp/unsafe-report.json" >/dev/null
echo "  [OK] probe argv-only/read-only budget discharge>=0.60 unsafe=0"
