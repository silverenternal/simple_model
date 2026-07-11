#!/usr/bin/env bash
set -euo pipefail
INPUT=""; OUT="generated/federation/cross-repo-impact.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --input|-i) INPUT="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac; done
[[ -f "$INPUT" ]] || { echo "--input required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq '{schema_version:"1.0",ok:true,change:.change,producers:(.producers//[]),consumers:(.consumers//[]),generated_clients:(.generated_clients//[]),deployments:(.deployments//[]),owner_approvals:(.owner_approvals//[]),unknown_consumer_risk:((.access.partial//false)==true),known_consumer_coverage:(if (.access.partial//false) then 0 else 1 end),contract_edges:(.contract_edges//[])}' "$INPUT" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Cross repo consumers=\(.consumers|length) coverage=\(.known_consumer_coverage)"' "$OUT"; fi
