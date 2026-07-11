#!/usr/bin/env bash
set -euo pipefail
QUERY=""; GRAPH="generated/intelligence/program-graph-v3.json"; OUT="generated/intelligence/mql-plan.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --query) QUERY="$2"; shift 2;; --graph) GRAPH="$2"; shift 2;; --output|-o) OUT="$2"; shift 2;; --json) JSON_OUT=1; shift;; *) echo "unknown arg: $1" >&2; exit 64;; esac; done
[[ -f "$QUERY" && -f "$GRAPH" ]] || { echo "--query and --graph required" >&2; exit 64; }
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
bash "$(dirname "$0")/mql_parse.sh" --input "$QUERY" --output "$tmp" --json >/dev/null
if jq -e '.traverse and ((.traverse.max_depth // 0)<1 or .traverse.max_depth>8 or .traverse.min_depth>.traverse.max_depth)' "$tmp" >/dev/null; then echo "unbounded or invalid traversal" >&2; exit 3; fi
nodes="$(jq '.summary.nodes' "$GRAPH")"; edges="$(jq '.summary.edges' "$GRAPH")"
jq -n --slurpfile q "$tmp" --argjson nodes "$nodes" --argjson edges "$edges" '
  $q[0] as $q | ($q.traverse.max_depth // 0) as $depth
  | {schema_version:"1.0",ok:true,normalized_query:$q,
     operators:([{"op":"node_scan","pattern":$q.match,"capture":$q.capture}] + (if $q.not then [{"op":"anti_match","patterns":$q.not}] else [] end) + (if $q.traverse then [{"op":"bounded_traverse","spec":$q.traverse}] else [] end) + [{"op":"quantify","mode":$q.quantifier}]),
     cost:{estimated_units:($nodes + ($edges * $depth)),nodes:$nodes,edges:$edges,max_depth:$depth},
     explain:["scan typed nodes","apply evidence predicates","apply negative patterns","execute bounded traversal","materialize captures","apply quantifier"]}' > "$OUT"
hash="$(jq -S -c '.normalized_query,.operators' "$OUT" | (sha256sum 2>/dev/null || shasum -a 256)|awk '{print $1}')"
jq --arg hash "$hash" '.plan_hash=$hash' "$OUT" > "$tmp"; mv "$tmp" "$OUT"; trap - EXIT
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"MQL plan cost=\(.cost.estimated_units) depth=\(.cost.max_depth)"' "$OUT"; fi
