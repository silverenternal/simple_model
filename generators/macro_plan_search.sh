#!/usr/bin/env bash
set -euo pipefail

OPERATORS=""
COMPOSITION=""
OUT="generated/macros/plan-search.json"
BUDGET=5
JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --operators) OPERATORS="$2"; shift 2 ;;
    --composition) COMPOSITION="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --budget) BUDGET="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
mkdir -p "$(dirname "$OUT")"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
if [[ -z "$OPERATORS" || ! -f "$OPERATORS" ]]; then OPERATORS="$tmp/operators.json"; bash "$(dirname "$0")/macro_operator_ir.sh" --output "$OPERATORS" --json >/dev/null; fi
if [[ -z "$COMPOSITION" || ! -f "$COMPOSITION" ]]; then COMPOSITION="$tmp/compose.json"; bash "$(dirname "$0")/macro_compose.sh" --operators "$OPERATORS" --output "$COMPOSITION" --json >/dev/null; fi
report=$(jq -n --argjson budget "$BUDGET" --slurpfile ops "$OPERATORS" --slurpfile comp "$COMPOSITION" '
  ($ops[0].operators // []) as $ops
  | ($comp[0].accepted_groups[0].operators // []) as $accepted_ids
  | [
      $ops[]? as $o
      | (($o.score_factors.maintainability // 0) + ($o.score_factors.risk // 0) + ($o.score_factors.test_cost // 0)) as $value
      | {
          id:$o.id, family:$o.family, mode:$o.mode,
          expected_value:$value,
          evidence_confidence:($o.preconditions.confidence_floor // 0.72),
          rollback_cost:(if (($o.write_effects // [])|length) > 2 then "medium" else "low" end),
          selected:((($accepted_ids|index($o.id)) != null) and ($value >= 0)),
          reason:(if (($accepted_ids|index($o.id)) == null) then "composition_rejected" elif $value < 0 then "dominated_by_risk" else "best_under_budget" end)
        }
    ] as $items
  | ($items|map(select(.selected))|sort_by(-.expected_value)|.[0:$budget]) as $selected
  | {
      schema_version:"1.0", ok:true,
      budget:$budget,
      summary:{candidates:($items|length), selected:($selected|length), rejected:($items|map(select(.selected|not))|length), stop_reason:"budget_or_candidates_exhausted"},
      selected:$selected,
      rejected:($items|map(select(.selected|not))),
      dominated:($items|map(select(.reason=="dominated_by_risk"))),
      deferred:($items|map(select(.mode=="review"))),
      gather_evidence:($items|map(select(.evidence_confidence < 0.8))),
      stable_hash:"pending"
    }')
hash=$(jq -c '{selected,rejected,summary}' <<<"$report" | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $1}')
report=$(jq --arg h "$hash" '.stable_hash=$h' <<<"$report")
printf '%s\n' "$report" > "$OUT"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Macro plan selected=" + (.summary.selected|tostring)' <<<"$report"; fi
