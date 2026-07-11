#!/usr/bin/env bash
set -euo pipefail
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
jq -n '{calls:[{idempotent:false,retry_requested:true},{idempotent:true,retry_requested:true}]}' > "$tmp/input.json"
bash generators/reliability_surface_scan.sh --input "$tmp/input.json" --output "$tmp/scan.json" --json >/dev/null
jq -e '.summary.simulate_capable_macros==3 and .summary.apply_capable_macros==2 and .summary.non_idempotent_retry_blocked==1 and .policies.non_idempotent_retry=="blocked_without_evidence"' "$tmp/scan.json" >/dev/null
echo "  [OK] reliability race/cancellation/leak policy"
