#!/usr/bin/env bash
set -euo pipefail
INPUT=""; OUT="generated/policy/approval-queue.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --input|-i) INPUT="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac; done
[[ -f "$INPUT" ]] || { echo "--input required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq '(.emergency_stop//false) as $stop | {schema_version:"2.0",ok:true,queue:([ .plans[]? | . as $p | {plan_id:.id,plan_hash:.plan_hash,scope:(.scope//[]),environment:(.environment//"local"),approval:(.approval//null),status:(if $stop then "blocked_emergency_stop" elif (.approval.plan_hash//"") != .plan_hash then "stale" elif (.approval.expires_at//"") < (.now//"9999") then "expired" else "pending" end)}]),summary:{stale_approval_uses:([.plans[]?|select((.approval.plan_hash//"") != .plan_hash)]|length),emergency_stop:$stop,unattributed_exceptions:0}}' "$INPUT" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Approval queue entries=\(.queue|length) stale=\(.summary.stale_approval_uses)"' "$OUT"; fi
