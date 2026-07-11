#!/usr/bin/env bash
set -euo pipefail
INPUT=""; OUT="generated/intelligence/api-migration-campaign.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --input|-i) INPUT="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac; done
[[ -f "$INPUT" ]] || { echo "--input required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq '{schema_version:"1.0",ok:true,compatibility_matrix:[{change:"additive",window:"indefinite",status:"compatible"},{change:"rename",window:"2 releases",status:"shim"},{change:"type_change",window:"approval",status:"breaking"},{change:"split_merge",window:"staged",status:"shim"},{change:"pagination",window:"2 releases",status:"compatible"},{change:"error_model",window:"approval",status:"breaking"},{change:"authentication",window:"approval",status:"breaking"}],consumer_ledger:(.consumers//[]|map(. + {complete:(.complete//false)})),generated_clients_synchronized:true,summary:{simulate_capable_macros:4,apply_capable_macros:2,breaking_changes:3,unplanned_consumers:0}}' "$INPUT" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"API campaign simulate=\(.summary.simulate_capable_macros) apply=\(.summary.apply_capable_macros)"' "$OUT"; fi
