#!/usr/bin/env bash
set -euo pipefail

OPERATORS=""
DYNAMIC=""
OUT="generated/macros/composition-report.json"
JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --operators) OPERATORS="$2"; shift 2 ;;
    --dynamic-edges) DYNAMIC="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
mkdir -p "$(dirname "$OUT")"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
if [[ -z "$OPERATORS" || ! -f "$OPERATORS" ]]; then OPERATORS="$tmp/operators.json"; bash "$(dirname "$0")/macro_operator_ir.sh" --output "$OPERATORS" --json >/dev/null; fi
if [[ -z "$DYNAMIC" || ! -f "$DYNAMIC" ]]; then DYNAMIC="$tmp/dynamic.json"; jq -n '{edges:[]}' > "$DYNAMIC"; fi
report=$(jq -n --slurpfile ops "$OPERATORS" --slurpfile dyn "$DYNAMIC" '
  ($ops[0].operators // []) as $ops
  | ($dyn[0].summary.blocks_safe_apply // 0) as $blocked_dyn
  | [
      range(0; $ops|length) as $i
      | range($i+1; $ops|length) as $j
      | $ops[$i] as $a | $ops[$j] as $b
      | ((($a.write_effects // []) + ($b.write_effects // [])) | group_by(.) | map(select(length>1)) | flatten) as $conflicts
      | select(($conflicts|length) > 0)
      | {left:$a.id, right:$b.id, type:"write_set_conflict", paths:$conflicts, decision:"reject_pair"}
    ] as $rejected
  | ($ops | map(select(([.id] as $id | all($rejected[]?; .left != $id[0] and .right != $id[0])))) | sort_by(.id)) as $accepted
  | {
      schema_version:"1.0", ok:true,
      summary:{operators:($ops|length), accepted:($accepted|length), rejected_pairs:($rejected|length), stages:(if ($accepted|length)>0 then 1 else 0 end), dynamic_blocks:$blocked_dyn},
      accepted_groups:[{stage:1, parallel:true, operators:($accepted|map(.id)), required_tests:($accepted|map(.affected_tests[]?)|unique|sort)}],
      rejected_pairs:$rejected,
      scheduler_tasks:($accepted|map({id:.id, command:"macro simulate", read_set:.input_selectors, write_set:.write_effects, resource_class:"codemod"})),
      policy:{reject_write_conflicts:true, reject_unsafe_dynamic_dependencies:($blocked_dyn > 0)}
    }')
printf '%s\n' "$report" > "$OUT"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Macro composition accepted=" + (.summary.accepted|tostring)' <<<"$report"; fi
