#!/usr/bin/env bash
set -euo pipefail
INPUT=""; OUT="generated/fleet/campaign-plan.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --input|-i) INPUT="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac; done
[[ -f "$INPUT" ]] || { echo "--input required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq '{schema_version:"1.0",ok:true,campaign_id,write_intent:(.write_intent//false),impact_analysis:{read_only:true,macro:(.macro//"unknown"),repositories:([.repositories[]|.id]|sort)},cohorts:(.cohorts // ([.repositories[]|.id] | _nwise(2) | to_entries | map({id:(.key|tostring),repositories:.value,canary:(.key==0)}))),idempotency_keys:([.repositories[]|{id, key:((.campaign_id+":"+ .id)|@base64)}]),summary:{repositories:([.repositories[]]|length),cohorts:((.cohorts//[])|length),read_only:true}}' "$INPUT" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Fleet plan repositories=\(.summary.repositories) cohorts=\(.summary.cohorts)"' "$OUT"; fi
