#!/usr/bin/env bash
set -euo pipefail
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
jq -n '{now:"2026-01-01",emergency_stop:false,plans:[{id:"p1",plan_hash:"hash-a",scope:["repo"],environment:"prod",approval:{plan_hash:"hash-a",expires_at:"9999",identity:"owner",proof_bundle_hash:"proof"}}]}' > "$tmp/input.json"
bash generators/approval_queue.sh --input "$tmp/input.json" --output "$tmp/queue.json" --json >/dev/null
jq -e '.summary.stale_approval_uses==0 and .queue[0].status=="pending"' "$tmp/queue.json" >/dev/null
jq '.plans[0].plan_hash="hash-b"' "$tmp/input.json" > "$tmp/stale.json"
bash generators/approval_queue.sh --input "$tmp/stale.json" --output "$tmp/stale-queue.json" --json >/dev/null
jq -e '.summary.stale_approval_uses==1 and .queue[0].status=="stale"' "$tmp/stale-queue.json" >/dev/null
jq '.emergency_stop=true' "$tmp/input.json" > "$tmp/stop.json"
bash generators/approval_queue.sh --input "$tmp/stop.json" --output "$tmp/stop-queue.json" --json >/dev/null
jq -e '.queue[0].status=="blocked_emergency_stop"' "$tmp/stop-queue.json" >/dev/null
jq -n '{exceptions:[{id:"w1",plan_hash:"hash",scope:["repo"],environment:"prod",expires_at:"9999",reason:"incident",identity:"oncall"}]}' > "$tmp/exceptions.json"
bash generators/exception_audit.sh --input "$tmp/exceptions.json" --output "$tmp/audit.json" --json >/dev/null
jq -e '.summary.unattributed_exceptions==0 and (.exceptions[0].required_proofs|index("rollback")) and (.exceptions[0].waiver_allowed==false)' "$tmp/audit.json" >/dev/null
echo "  [OK] policy approvals hash-bound/stale/emergency-stop/waiver audit"

