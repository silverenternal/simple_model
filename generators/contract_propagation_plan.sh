#!/usr/bin/env bash
set -euo pipefail
INPUT=""; OUT="generated/federation/contract-propagation-plan.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --input|-i) INPUT="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac; done
[[ -f "$INPUT" ]] || { echo "--input required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq '{schema_version:"1.0",ok:true,stages:[{id:"install-shim",kind:"compatibility_shim",requires:["producer_approval"],status:"planned"},{id:"migrate-consumers",kind:"consumer_updates",requires:["install-shim","owner_approvals"],consumers:(.consumers//[]),status:"planned"},{id:"remove-shim",kind:"shim_removal",requires:["consumer_completion_evidence"],status:"planned"}],rollback_order:["remove-shim","migrate-consumers","install-shim"],published_versions:(.published_versions//[]),deployed_dependencies:(.deployed_dependencies//[]),unknown_consumer_risk:(.unknown_consumer_risk//false),summary:{known_consumer_coverage:(.known_consumer_coverage//0),out_of_order_breaking_rollouts:0,owner_approvals:(.owner_approvals//[]|length)}}' "$INPUT" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Propagation stages=\(.stages|length) coverage=\(.summary.known_consumer_coverage)"' "$OUT"; fi
