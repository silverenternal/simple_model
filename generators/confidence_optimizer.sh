#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="."
STRUCT="${STRUCT_FILE:-./struct.json}"
GRAPH=""
PRECONDITIONS=""
OUT="generated/optimization/confidence-plan.json"
JSON_OUT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --struct|-s) STRUCT="$2"; shift 2 ;;
    --graph) GRAPH="$2"; shift 2 ;;
    --preconditions) PRECONDITIONS="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

ROOT="$(cd "$ROOT" && pwd)"
STRUCT="$(cd "$(dirname "$STRUCT")" && pwd)/$(basename "$STRUCT")"
mkdir -p "$(dirname "$OUT")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if [[ -z "$GRAPH" ]]; then
  GRAPH="$tmp/graph.json"
  bash "$SELF_DIR/semantic_graph_incremental.sh" --root "$ROOT" --struct "$STRUCT" --output "$GRAPH" --diff-output "$tmp/diff.json" --json >/dev/null
fi
if [[ -z "$PRECONDITIONS" ]]; then
  PRECONDITIONS="$tmp/preconditions.json"
  bash "$SELF_DIR/macro_preconditions.sh" --root "$ROOT" --struct "$STRUCT" --graph "$GRAPH" --output "$PRECONDITIONS" --json >/dev/null
fi

report=$(jq -n --arg root "$ROOT" --arg struct "$STRUCT" --slurpfile graph "$GRAPH" --slurpfile pre "$PRECONDITIONS" '
  ($graph[0]) as $g
  | ($pre[0].results // []) as $macros
  | [
      $macros[]?
      | (.evidence.matching_nodes // 0) as $nodes
      | (.evidence.blocked_dynamic_edges // 0) as $blocked
      | (.confidence_floor // 0.8) as $floor
      | (if .decision == "safe_apply" then "safe-now"
         elif .decision == "review_required" then "review-first"
         elif .decision == "evidence_missing" then "gather-evidence"
         else "do-not-touch" end) as $queue
      | {
          id:.macro_id,
          queue:$queue,
          expected_value:((($nodes + 1) * 0.1) - ($blocked * 0.2)),
          evidence_confidence:$floor,
          macro_readiness:.decision,
          affected_tests:(.affected_tests // []),
          runtime_cost:"bounded",
          rollback_cost:(if ((.write_set // [])|length) > 3 then "medium" else "low" end),
          dynamic_risk:(if $blocked > 0 then "high" else "managed" end),
          explanation:(if $queue=="safe-now" then "preconditions passed with sufficient graph evidence" elif $queue=="review-first" then "requires human review before apply" elif $queue=="gather-evidence" then "missing semantic evidence" else "policy denied" end)
        }
    ] as $items
  | {
      schema_version:"1.0", ok:true, root:$root, struct:$struct,
      summary:{
        recommendations:($items|length),
        safe_now:($items|map(select(.queue=="safe-now"))|length),
        review_first:($items|map(select(.queue=="review-first"))|length),
        gather_evidence:($items|map(select(.queue=="gather-evidence"))|length),
        do_not_touch:($items|map(select(.queue=="do-not-touch"))|length),
        graph_nodes:($g.summary.nodes // 0),
        graph_edges:($g.summary.edges // 0)
      },
      queues:{
        safe_now:($items|map(select(.queue=="safe-now"))|sort_by(-.expected_value)),
        review_first:($items|map(select(.queue=="review-first"))|sort_by(-.expected_value)),
        gather_evidence:($items|map(select(.queue=="gather-evidence"))|sort_by(-.expected_value)),
        do_not_touch:($items|map(select(.queue=="do-not-touch"))|sort_by(-.expected_value))
      },
      policy:{low_confidence_cannot_safe_apply:true, rank_by_expected_value_and_risk:true}
    }')

printf '%s\n' "$report" > "$OUT"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Confidence plan safe_now=" + (.summary.safe_now|tostring) + " review=" + (.summary.review_first|tostring)' <<<"$report"; fi
