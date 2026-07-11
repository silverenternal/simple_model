#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="."
STRUCT="${STRUCT_FILE:-./struct.json}"
OUT="generated/intelligence/semantic-graph.json"
DIFF_OUT="generated/intelligence/semantic-graph-diff.json"
CACHE="generated/.cache/simple_model/artifacts/index.json"
JSON_OUT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --struct|-s) STRUCT="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --diff-output) DIFF_OUT="$2"; shift 2 ;;
    --cache) CACHE="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

ROOT="$(cd "$ROOT" && pwd)"
STRUCT="$(cd "$(dirname "$STRUCT")" && pwd)/$(basename "$STRUCT")"
mkdir -p "$(dirname "$OUT")" "$(dirname "$DIFF_OUT")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

old_graph="$tmp/old.json"
if [[ -f "$OUT" ]]; then cp "$OUT" "$old_graph"; else jq -n '{nodes:[],edges:[],graph_hash:""}' > "$old_graph"; fi

inputs="struct.json,generators/semantic_graph.sh,generators/tree_sitter_scan.sh,generators/parser_tier_registry.sh"
lookup=$(bash "$SELF_DIR/artifact_cache.sh" --cache "$CACHE" --root "$ROOT" --command semantic_graph_v11 --inputs "$inputs" --lookup --json)
cache_hit=$(jq -r '.hit' <<<"$lookup")

if [[ "$cache_hit" == "true" ]]; then
  jq '.entry.result' <<<"$lookup" > "$OUT"
else
  bash "$SELF_DIR/semantic_graph.sh" --root "$ROOT" --struct "$STRUCT" --output "$OUT" --json >/dev/null
  bash "$SELF_DIR/parser_tier_registry.sh" --root "$ROOT" --output "$tmp/parser-tiers.json" --json >/dev/null
  bash "$SELF_DIR/symbol_identity.sh" --root "$ROOT" --struct "$STRUCT" --tiers "$tmp/parser-tiers.json" --output "$tmp/symbol-index.json" --json >/dev/null
  bash "$SELF_DIR/dynamic_edge_resolver.sh" --root "$ROOT" --struct "$STRUCT" --symbols "$tmp/symbol-index.json" --output "$tmp/dynamic-edges.json" --json >/dev/null
  jq --slurpfile tiers "$tmp/parser-tiers.json" --slurpfile symbols "$tmp/symbol-index.json" --slurpfile dyn "$tmp/dynamic-edges.json" '
    .schema_version="2.1"
    | .parser_tiers=$tiers[0].summary
    | .symbol_identity=$symbols[0].summary
    | .dynamic_edges=$dyn[0].summary
    | .nodes = (.nodes + ($symbols[0].symbols // [] | map({id:.stable_id, kind:("symbol_identity." + .kind), name, path, confidence, hash:.invalidation_key, evidence:{source:"symbol_identity", parser_tier}})) | unique_by(.id) | sort_by(.id))
    | .edges = (.edges + ($dyn[0].edges // [] | map({id, kind, from, to, confidence, evidence:{source:"dynamic_edge_resolver", trust_state, evidence_class}})) | unique_by(.id) | sort_by(.id))
  ' "$OUT" > "$tmp/enriched.json"
  graph_hash=$(jq -c '{nodes:[.nodes[].id],edges:[.edges[].id]}' "$tmp/enriched.json" | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $1}')
  jq --arg graph_hash "$graph_hash" '.graph_hash=$graph_hash | .summary.nodes=(.nodes|length) | .summary.edges=(.edges|length)' "$tmp/enriched.json" > "$OUT"
  bash "$SELF_DIR/artifact_cache.sh" --cache "$CACHE" --root "$ROOT" --command semantic_graph_v11 --inputs "$inputs" --result "$OUT" --store --json >/dev/null
fi

diff=$(jq -n --slurpfile old "$old_graph" --slurpfile new "$OUT" --argjson cache_hit "$cache_hit" '
  ($old[0] // {nodes:[],edges:[],graph_hash:""}) as $old
  | ($new[0] // {nodes:[],edges:[],graph_hash:""}) as $new
  | ($old.nodes // [] | map(.id)) as $old_nodes
  | ($new.nodes // [] | map(.id)) as $new_nodes
  | ($old.edges // [] | map(.id)) as $old_edges
  | ($new.edges // [] | map(.id)) as $new_edges
  | {
      schema_version:"1.0", ok:true, cache_hit:$cache_hit,
      old_hash:($old.graph_hash // ""), new_hash:($new.graph_hash // ""),
      changed:(($old.graph_hash // "") != ($new.graph_hash // "")),
      summary:{
        added_nodes:($new_nodes - $old_nodes | length),
        removed_nodes:($old_nodes - $new_nodes | length),
        added_edges:($new_edges - $old_edges | length),
        removed_edges:($old_edges - $new_edges | length),
        confidence_shifted:0
      },
      added_nodes:($new_nodes - $old_nodes),
      removed_nodes:($old_nodes - $new_nodes),
      added_edges:($new_edges - $old_edges),
      removed_edges:($old_edges - $new_edges),
      invalidation:{content_addressed:true, partial_rebuild_ready:true}
    }')
printf '%s\n' "$diff" > "$DIFF_OUT"
if [[ "$JSON_OUT" == "1" ]]; then
  jq -n --slurpfile graph "$OUT" --slurpfile diff "$DIFF_OUT" '{schema_version:"1.0", ok:true, graph:$graph[0], diff:$diff[0]}'
else
  jq -r '"Incremental graph changed=" + (.changed|tostring) + " added_nodes=" + (.summary.added_nodes|tostring)' "$DIFF_OUT"
fi
