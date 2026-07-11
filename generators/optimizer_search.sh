#!/usr/bin/env bash
set -euo pipefail

GRAPH="generated/optimization/graph.json"
OUT="generated/optimization/search.json"
MODE="greedy"
BUDGET=5
JSON_OUT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --graph) GRAPH="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    --budget) BUDGET="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

[[ -f "$GRAPH" ]] || { echo "[FAIL] graph not found: $GRAPH" >&2; exit 2; }
mkdir -p "$(dirname "$OUT")"

report=$(jq -n --arg mode "$MODE" --argjson budget "$BUDGET" --slurpfile graph_file "$GRAPH" '
  ($graph_file[0]) as $g
  | def risk_rank($r):
      if ($r|test("unsafe|critical")) then 4
      elif ($r|test("unverified|high")) then 3
      elif ($r|test("medium")) then 2
      else 1 end;
    [
      $g.nodes[]? | select(.kind=="macro_candidate")
      | (.evidence.writes // []) as $writes
      | (risk_rank(.risk // "medium")) as $risk
      | {
          id:.id,
          macro_id:.name,
          risk:(.risk // "medium"),
          target:{component:(.component // ""), path:(.path // "")},
          score_delta:((.score_weight // 1) * 10 - $risk * 2 - (($writes|length) * 0.5)),
          rollback_cost:(($writes|length) + $risk),
          test_cost:($risk + (($writes|length) * 2)),
          dynamic_penalty:(if (.risk|test("dynamic_unsafe|dynamic_unverified")) then 10 else 0 end),
          reason:(.evidence.reason // "candidate from optimization graph"),
          writes:$writes,
          graph_node:.id
        }
    ] | sort_by(-.score_delta, .rollback_cost, .macro_id, .id) as $ranked
  | ($ranked | map(select(.score_delta > 0)) | .[0:$budget]) as $selected
  | {
      schema_version:"1.0",
      ok:true,
      mode:$mode,
      graph_hash:$g.graph_hash,
      budget:$budget,
      summary:{candidates:($ranked|length), selected:($selected|length), rejected:(($ranked|length)-($selected|length)), best_delta:($ranked[0].score_delta // 0)},
      selected:$selected,
      rejected:($ranked - $selected),
      decision_trace:($ranked | map(. as $c | {id, macro_id, score_delta, risk, selected:($selected|map(.id)|index($c.id) != null), reason:(if ($selected|map(.id)|index($c.id) != null) then "selected_positive_delta" else "rejected_by_budget_or_nonpositive_delta" end)})),
      stop_reason:(if ($selected|length) == 0 then "no_positive_delta" elif ($selected|length) >= $budget then "budget_exhausted" else "candidate_pool_exhausted" end)
    }')

printf '%s\n' "$report" > "$OUT"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Optimizer Search selected=" + (.summary.selected|tostring) + " stop=" + .stop_reason' <<<"$report"; fi
