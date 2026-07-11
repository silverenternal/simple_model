#!/usr/bin/env bash
set -euo pipefail

LEDGER=""
OUT="generated/macros/family-rankings.json"
JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ledger) LEDGER="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
mkdir -p "$(dirname "$OUT")"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
if [[ -z "$LEDGER" || ! -f "$LEDGER" ]]; then LEDGER="$tmp/ledger.json"; bash "$(dirname "$0")/macro_outcome_ledger.sh" --output "$LEDGER" --json >/dev/null; fi
report=$(jq -n --slurpfile ledger "$LEDGER" '
  ($ledger[0].entries // []) as $entries
  | ($entries | group_by(.operator_id|split(".")[0]) | map({
      family:(.[0].operator_id|split(".")[0]),
      observations:length,
      value_score:([.[].score_delta] | add // 0),
      safety_score:(if all(.[]; .rollback_result=="ok") then 1 else 0 end),
      generality_score:(map(.repo_fingerprint)|unique|length),
      maturity_score:(if length >= 1 then 0.7 else 0 end),
      promotion_score:(([.[].score_delta] | add // 0) + (if all(.[]; .rollback_result=="ok") then 1 else 0 end)),
      recommendation:(if all(.[]; .rollback_result=="ok") then "keep_or_promote" else "review_only" end)
    }) | sort_by(-.promotion_score)) as $families
  | {
      schema_version:"1.0", ok:true,
      summary:{families:($families|length), promotable:($families|map(select(.recommendation=="keep_or_promote"))|length), review_only:($families|map(select(.recommendation!="keep_or_promote"))|length)},
      families:$families,
      policy:{rank_by_observed_value:true, retire_weak_families:true}
    }')
printf '%s\n' "$report" > "$OUT"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Macro families=" + (.summary.families|tostring)' <<<"$report"; fi
