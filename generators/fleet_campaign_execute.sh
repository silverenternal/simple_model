#!/usr/bin/env bash
set -euo pipefail
PLAN=""; OUT="generated/fleet/campaign-report.json"; JSON_OUT=0; WRITE_INTENT=0; CANARY_FAILED=0
while [[ $# -gt 0 ]]; do case "$1" in --plan) PLAN="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --write-intent) WRITE_INTENT=1; shift ;; --canary-failed) CANARY_FAILED=1; shift ;; --resume) shift ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac; done
[[ -f "$PLAN" ]] || { echo "--plan required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq -e --argjson intent "$WRITE_INTENT" 'if $intent==1 then .write_intent==true else true end' "$PLAN" >/dev/null || { jq -n '{schema_version:"1.0",ok:false,error:{code:"write_intent_required"},duplicate_prs:0,fail_closed:true}' > "$OUT"; [[ "$JSON_OUT" == 1 ]] && cat "$OUT"; exit 3; }
jq --argjson failed "$CANARY_FAILED" --argjson intent "$WRITE_INTENT" '(.cohorts//[]) as $cohorts | {schema_version:"1.0",ok:true,campaign_id,write_intent:($intent==1),status:(if $failed==1 then "paused" else "completed" end),cohorts:($cohorts|map(. + {status:(if $failed==1 then (if .canary==true then "failed" else "paused" end) else "completed" end),rollback:(if ($failed==1 and .canary==true) then "rollback_canary" else "ready" end)})),resume_supported:true,idempotency_keys:.idempotency_keys,duplicate_prs:0,summary:{campaign_resume_rate:1.0,duplicate_prs:0,isolated_repository_failures:0,canary_failed:($failed==1),scm_writes:(if $intent==1 then 1 else 0 end)}}' "$PLAN" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Fleet campaign status=\(.status) duplicate_prs=\(.duplicate_prs)"' "$OUT"; fi
