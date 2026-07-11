#!/usr/bin/env bash
set -euo pipefail

SEARCH="generated/optimization/search.json"
GRAPH="generated/optimization/graph.json"
OUT_DIR="generated/optimization"
JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --search) SEARCH="$2"; shift 2 ;;
    --graph) GRAPH="$2"; shift 2 ;;
    --output-dir) OUT_DIR="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
[[ -f "$SEARCH" && -f "$GRAPH" ]] || { echo "[FAIL] missing --search or --graph" >&2; exit 2; }
mkdir -p "$OUT_DIR"
report=$(jq -n --slurpfile search "$SEARCH" --slurpfile graph "$GRAPH" '
  ($search[0]) as $s | ($graph[0]) as $g
  | {
      schema_version:"1.0", ok:true, graph_hash:$g.graph_hash, stop_reason:$s.stop_reason,
      summary:{selected:(($s.selected // [])|length), rejected:(($s.rejected // [])|length), graph_nodes:($g.summary.nodes // 0)},
      selected:(($s.selected // [])|map(. + {explanation:{why:"positive calibrated score under policy budget", affected_tests:"from test impact DAG", rollback:"use macro rollback manifest", evidence_node:.graph_node}})),
      rejected:(($s.rejected // [])|map(. + {explanation:{why:"budget, non-positive delta, or risk constraint", next:"add evidence or lower rollback cost"}})),
      review_checklist:["inspect evidence paths","run macro simulation","run affected-check","verify rollback manifest","review dynamic policy"]
    }')
printf '%s\n' "$report" > "$OUT_DIR/optimizer-report.json"
{
  echo "# Optimizer Report"
  echo
  jq -r '"- graph hash: " + .graph_hash, "- selected: " + (.summary.selected|tostring), "- rejected: " + (.summary.rejected|tostring), "- stop reason: " + .stop_reason' <<<"$report"
  echo
  echo "## Selected"
  jq -r '.selected[]? | "- " + .macro_id + " delta=" + (.score_delta|tostring) + " risk=" + .risk + " reason=" + .explanation.why' <<<"$report"
  echo
  echo "## Rejected"
  jq -r '.rejected[]? | "- " + .macro_id + " reason=" + .explanation.why' <<<"$report"
} > "$OUT_DIR/optimizer-report.md"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else cat "$OUT_DIR/optimizer-report.md"; fi
