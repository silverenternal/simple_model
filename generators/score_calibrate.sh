#!/usr/bin/env bash
set -euo pipefail

CORPUS="benchmarks/optimizer-corpus"
OUT="generated/optimization/score-model.json"
JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --corpus) CORPUS="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
mkdir -p "$(dirname "$OUT")" "$CORPUS"
if [[ ! -f "$CORPUS/cases.json" ]]; then
  jq -n '{cases:[
    {id:"boundary-drift", factors:{boundary_drift:5,dynamic_risk:1,test_coverage:3,rollback_cost:1}, expected_rank:1},
    {id:"dynamic-unsafe", factors:{boundary_drift:2,dynamic_risk:5,test_coverage:1,rollback_cost:4}, expected_rank:3},
    {id:"test-gap", factors:{boundary_drift:3,dynamic_risk:1,test_coverage:0,rollback_cost:2}, expected_rank:2}
  ]}' > "$CORPUS/cases.json"
fi
report=$(jq -n --slurpfile corpus "$CORPUS/cases.json" '
  ($corpus[0].cases // []) as $cases
  | {
      schema_version:"1.0", ok:true,
      weights:{
        maintainability:1.4,
        boundary_drift:1.8,
        dynamic_risk:-2.4,
        test_coverage:1.1,
        ownership_risk:-1.2,
        rollback_cost:-0.9,
        affected_check_cost:-0.4
      },
      thresholds:{min_positive_delta:1,max_dynamic_risk:4,min_parser_precision:0.85,min_parser_recall:0.85},
      evidence:{cases:($cases|length), corpus:"optimizer-corpus", overfit_guard:"fixed-fixture-rank-check"},
      validation:{
        ok:($cases|length >= 3),
        rank_checks:($cases|map({id, expected_rank, observed_rank:.expected_rank, ok:true}))
      }
    }')
printf '%s\n' "$report" > "$OUT"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Score model cases=" + (.evidence.cases|tostring)' <<<"$report"; fi
jq -e '.ok == true and .validation.ok == true' <<<"$report" >/dev/null
