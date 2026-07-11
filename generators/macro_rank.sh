#!/usr/bin/env bash
set -euo pipefail
SUGGESTIONS="generated/optimization/macro-suggestions.json"
JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --suggestions) SUGGESTIONS="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
[[ -f "$SUGGESTIONS" ]] || { echo "[FAIL] suggestions not found: $SUGGESTIONS" >&2; exit 2; }
report=$(jq '
  def risk_score($r): {"low":1,"medium":2,"high":3,"critical":4}[$r] // 4;
  .specs as $specs
  | ($specs | map(. + {
      rank_score: (
        (if .trigger == "undeclared_exports" then 70 elif .trigger == "undeclared_import" then 65 elif .trigger == "multi_module_single_struct" then 40 else 25 end)
        - (risk_score(.safety.risk) * 5)
        + (if .safety.auto_apply == true then 5 else 0 end)
      ),
      rank_evidence:{trigger:.trigger, risk:.safety.risk, auto_apply:(.safety.auto_apply // false)}
    }) | sort_by(-.rank_score, .id)) as $ranked
  | {schema_version:"1.0", ok:true, summary:{candidates:($ranked|length), top_score:(($ranked[0].rank_score) // 0)}, ranked:$ranked}
' "$SUGGESTIONS")
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Macro Rank candidates=" + (.summary.candidates|tostring)' <<<"$report"; fi
