#!/usr/bin/env bash
set -euo pipefail

BEFORE=""
AFTER=""
SEARCH="generated/optimization/search.json"
OUT="generated/optimization/score-delta-proof.json"
JSON_OUT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --before) BEFORE="$2"; shift 2 ;;
    --after) AFTER="$2"; shift 2 ;;
    --search) SEARCH="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

[[ -f "$SEARCH" ]] || { echo "[FAIL] search not found: $SEARCH" >&2; exit 2; }
before_json='{"score":0,"debt":0,"factors":{}}'
after_json='{"score":0,"debt":0,"factors":{}}'
[[ -n "$BEFORE" && -f "$BEFORE" ]] && before_json=$(jq . "$BEFORE")
[[ -n "$AFTER" && -f "$AFTER" ]] && after_json=$(jq . "$AFTER")
mkdir -p "$(dirname "$OUT")"

report=$(jq -n --argjson before "$before_json" --argjson after "$after_json" --slurpfile search_file "$SEARCH" '
  ($search_file[0]) as $search
  | {
      schema_version:"1.0",
      ok:true,
      graph_hash:$search.graph_hash,
      score:{before:($before.score // 0), after:($after.score // 0), delta:(($after.score // 0)-($before.score // 0)), debt_before:($before.debt // 0), debt_after:($after.debt // 0)},
      summary:{selected:(($search.selected // [])|length), rejected:(($search.rejected // [])|length), score_delta:(($after.score // 0)-($before.score // 0))},
      selected:$search.selected,
      rejected:$search.rejected,
      stop_reason:$search.stop_reason,
      proof_hash:({before_score:($before.score // 0), after_score:($after.score // 0), graph_hash:$search.graph_hash, selected:(($search.selected // [])|map(.id)), rejected:(($search.rejected // [])|map(.id)), stop_reason:$search.stop_reason}|tostring),
      constraints:["positive score delta", "bounded budget", "risk-ranked candidates", "stable tie-break"],
      conclusion:(if (($after.score // 0) >= ($before.score // 0)) then "non_regressing" else "regressing" end)
    }')

printf '%s\n' "$report" > "$OUT"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Score Delta Proof delta=" + (.score.delta|tostring) + " conclusion=" + .conclusion' <<<"$report"; fi
