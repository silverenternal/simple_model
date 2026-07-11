#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="."
STRUCT="${STRUCT_FILE:-./struct.json}"
MACRO=""
GRAPH=""
DYNAMIC=""
OUT="generated/macros/precondition-report.json"
JSON_OUT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --struct|-s) STRUCT="$2"; shift 2 ;;
    --macro) MACRO="$2"; shift 2 ;;
    --graph) GRAPH="$2"; shift 2 ;;
    --dynamic-edges) DYNAMIC="$2"; shift 2 ;;
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
  GRAPH="$tmp/semantic-graph.json"
  bash "$SELF_DIR/semantic_graph_incremental.sh" --root "$ROOT" --struct "$STRUCT" --output "$GRAPH" --diff-output "$tmp/diff.json" --json >/dev/null
fi
if [[ -z "$DYNAMIC" ]]; then
  DYNAMIC="$tmp/dynamic-edges.json"
  bash "$SELF_DIR/dynamic_edge_resolver.sh" --root "$ROOT" --struct "$STRUCT" --output "$DYNAMIC" --json >/dev/null
fi

if [[ -n "$MACRO" && -f "$MACRO" ]]; then
  cp "$MACRO" "$tmp/macros.json"
else
  jq -n '{macros:[
    {id:"boundary-repair.safe-export", mode:"apply", preconditions:{graph_nodes:["symbol_identity"], edge_types:["symbol_exports_interface"], confidence_floor:0.72, dynamic_evidence:"weak_allowed"}, write_set:["src/**","generated/**"], affected_tests:["semantic"], formatter_policy:"language-default"},
    {id:"framework-repair.dynamic-route", mode:"simulate", preconditions:{graph_nodes:["dynamic"], edge_types:["route_binding"], confidence_floor:0.78, dynamic_evidence:"observed_or_generated"}, write_set:["routes/**","src/**"], affected_tests:["framework"], formatter_policy:"language-default"}
  ]}' > "$tmp/macros.json"
fi

report=$(jq -n --arg root "$ROOT" --arg struct "$STRUCT" --slurpfile macros "$tmp/macros.json" --slurpfile graph "$GRAPH" --slurpfile dyn "$DYNAMIC" '
  ($macros[0].macros // $macros[0].todos // [$macros[0]]) as $macros
  | ($graph[0].nodes // []) as $nodes
  | ($graph[0].edges // []) as $edges
  | ($dyn[0].edges // []) as $dyn_edges
  | [
      $macros[]? as $m
      | ($m.preconditions // {}) as $p
      | ($p.confidence_floor // 0.8) as $floor
      | ($nodes | map(select((.confidence // 0) >= $floor)) | length) as $conf_nodes
      | ($edges | map(. as $e | select((($p.edge_types // [])|length == 0) or ((($p.edge_types // []) | index($e.kind)) != null))) | length) as $edge_hits
      | ($dyn_edges | map(select(.blocks_safe_apply)) | length) as $blocked_dyn
      | (if $conf_nodes == 0 then "evidence_missing"
         elif $edge_hits == 0 and (($p.edge_types // [])|length) > 0 then "evidence_missing"
         elif ($p.dynamic_evidence // "none") == "trusted_only" and $blocked_dyn > 0 then "review_required"
         elif ($m.mode // "review") == "apply" then "safe_apply"
         elif ($m.mode // "review") == "simulate" then "review_required"
         else "review_required" end) as $decision
      | {
          macro_id:($m.id // "unknown"),
          decision:$decision,
          confidence_floor:$floor,
          evidence:{matching_nodes:$conf_nodes, matching_edges:$edge_hits, blocked_dynamic_edges:$blocked_dyn},
          missing:([
            (if $conf_nodes == 0 then "graph_nodes_above_confidence_floor" else empty end),
            (if $edge_hits == 0 and (($p.edge_types // [])|length) > 0 then "required_edge_types" else empty end),
            (if ($p.dynamic_evidence // "none") == "trusted_only" and $blocked_dyn > 0 then "trusted_dynamic_evidence" else empty end)
          ]),
          write_set:($m.write_set // []),
          affected_tests:($m.affected_tests // [])
        }
    ] as $results
  | {
      schema_version:"1.0", ok:true, root:$root, struct:$struct,
      summary:{
        macros:($results|length),
        safe_apply:($results|map(select(.decision=="safe_apply"))|length),
        review_required:($results|map(select(.decision=="review_required"))|length),
        evidence_missing:($results|map(select(.decision=="evidence_missing"))|length),
        policy_denied:($results|map(select(.decision=="policy_denied"))|length)
      },
      results:$results,
      policy:{apply_requires_safe_apply:true, low_confidence_blocks_apply:true}
    }')

printf '%s\n' "$report" > "$OUT"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Macro preconditions safe_apply=" + (.summary.safe_apply|tostring) + " review=" + (.summary.review_required|tostring)' <<<"$report"; fi
