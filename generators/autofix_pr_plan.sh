#!/usr/bin/env bash
set -euo pipefail
PLAN="generated/optimization/plan.json"
JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan) PLAN="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
[[ -f "$PLAN" ]] || { echo "[FAIL] plan not found: $PLAN" >&2; exit 2; }
report=$(jq '{
  schema_version:"1.0",
  ok:true,
  mode:"dry-run",
  summary:{
    eligible:([.actions[]?|select(.auto_apply==true and (.risk=="low" or .risk=="medium") and (((.dynamic.missing_observations // [])|length)==0) and (((.dynamic.unsafe_nodes // [])|length)==0))]|length),
    review_only:([.actions[]?|select((.auto_apply!=true) or (.risk=="high" or .risk=="critical") or (((.dynamic.missing_observations // [])|length)>0) or (((.dynamic.unsafe_nodes // [])|length)>0))]|length)
  },
  branch:"simple-model/autofix",
  pull_request:{create:false,title:"simple_model autofix macros", body:"Generated dry-run plan."},
  eligible:[.actions[]?|select(.auto_apply==true and (.risk=="low" or .risk=="medium") and (((.dynamic.missing_observations // [])|length)==0) and (((.dynamic.unsafe_nodes // [])|length)==0))],
  review_only:[.actions[]?|select((.auto_apply!=true) or (.risk=="high" or .risk=="critical") or (((.dynamic.missing_observations // [])|length)>0) or (((.dynamic.unsafe_nodes // [])|length)>0))]
}' "$PLAN")
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Autofix PR eligible=" + (.summary.eligible|tostring) + " review_only=" + (.summary.review_only|tostring)' <<<"$report"; fi
