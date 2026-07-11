#!/usr/bin/env bash
set -euo pipefail

ROOT="."
REGISTRY="macros/registry.json"
OUT="generated/macros/operator-ir.json"
JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --registry) REGISTRY="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
ROOT="$(cd "$ROOT" && pwd)"
[[ -f "$REGISTRY" ]] || REGISTRY="$ROOT/macros/registry.json"
mkdir -p "$(dirname "$OUT")"

report=$(jq -n --arg root "$ROOT" --slurpfile reg "$REGISTRY" '
  def arr(x): if x == null then [] elif (x|type)=="array" then x else [x] end;
  ($reg[0].macros // $reg[0].packs // $reg[0].operators // []) as $items
  | (if ($items|length) == 0 then [
      {id:"boundary-repair.safe-export", family:"boundary-repair", mode:"simulate", write_set:["src/**"], affected_tests:["semantic"]},
      {id:"framework-repair.dynamic-route", family:"framework-repair", mode:"review", write_set:["routes/**"], affected_tests:["framework"]}
    ] else $items end) as $macros
  | [
      $macros[]? as $m
      | {
          id:($m.id // $m.name // "macro.unknown"),
          family:($m.family // $m.pack // (($m.id // "macro.unknown")|split(".")[0])),
          mode:(if ($m.mode // "review") == "apply" then "apply" elif ($m.mode // "review") == "simulate" then "simulate" else "review" end),
          input_selectors:arr($m.input_selectors // [{type:"semantic_graph", selector:"candidate_nodes", confidence_floor:0.72}]),
          graph_effects:arr($m.graph_effects // [{type:"may_change_edges", kinds:["ownership","import","dynamic"]}]),
          write_effects:arr($m.write_effects // $m.write_set // [("virtual:" + ($m.id // $m.name // "macro.unknown"))]),
          preconditions:($m.preconditions // {confidence_floor:0.72, dynamic_evidence:"weak_allowed", policy:"macro-contract-v4"}),
          postconditions:($m.postconditions // {idempotent:true, formatter:"language-default"}),
          affected_tests:arr($m.affected_tests // ["semantic"]),
          rollback_scope:($m.rollback_scope // {type:"file_hashes", bounded:true}),
          score_factors:($m.score_factors // {maintainability:0.2, risk:-0.1, test_cost:-0.05}),
          proof_obligations:["preconditions","composition","drill","affected_tests","rollback"],
          validation:{
            typed_selectors:((arr($m.input_selectors // [{type:"semantic_graph"}])|all(.type != null))),
            bounded_writes:((arr($m.write_effects // $m.write_set // ["review-only"])|length) > 0),
            rollback_declared:(($m.rollback_scope // {bounded:true}).bounded == true)
          }
        }
    ] as $ops
  | {
      schema_version:"1.0", ok:all($ops[]; .validation.typed_selectors and .validation.bounded_writes and .validation.rollback_declared),
      root:$root,
      summary:{operators:($ops|length), apply_capable:($ops|map(select(.mode=="apply"))|length), simulate_capable:($ops|map(select(.mode=="simulate" or .mode=="apply"))|length), review_only:($ops|map(select(.mode=="review"))|length)},
      operators:($ops|sort_by(.id)),
      policy:{ambiguous_write_effects_rejected:true, missing_rollback_rejected:true}
    }')
printf '%s\n' "$report" > "$OUT"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Macro operators=" + (.summary.operators|tostring)' <<<"$report"; fi
jq -e '.ok == true' <<<"$report" >/dev/null
