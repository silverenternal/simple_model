#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="."
STRUCT="${STRUCT_FILE:-./struct.json}"
OUT="generated/intelligence/semantic-graph.json"
JSON_OUT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --struct|-s) STRUCT="$2"; shift 2 ;;
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

bash "$SELF_DIR/tree_sitter_scan.sh" --root "$ROOT" --output "$tmp/tree.json" --json >/dev/null
bash "$SELF_DIR/lsp_symbol_index.sh" --root "$ROOT" --output "$tmp/lsp.json" --json >/dev/null
bash "$SELF_DIR/semantic_interface_ir.sh" --root "$ROOT" --struct "$STRUCT" --output "$tmp/ir-out.json" --json > "$tmp/ir.json" 2>/dev/null || jq -n '{nodes:[],dynamic_surfaces:{nodes:[]},summary:{}}' > "$tmp/ir.json"
bash "$SELF_DIR/test_graph.sh" --root "$ROOT" --struct "$STRUCT" --json > "$tmp/tests.json" 2>/dev/null || jq -n '{tests:[],summary:{}}' > "$tmp/tests.json"

report=$(jq -n --arg root "$ROOT" --arg struct "$STRUCT" --slurpfile tree "$tmp/tree.json" --slurpfile lsp "$tmp/lsp.json" --slurpfile ir "$tmp/ir.json" --slurpfile tests "$tmp/tests.json" '
  def sid($parts): ($parts | join(":") | gsub("[^A-Za-z0-9_.:-]"; "_"));
  ($tree[0] // {facts:[]}) as $tree
  | ($lsp[0] // {workspaces:[]}) as $lsp
  | ($ir[0] // {nodes:[],dynamic_surfaces:{nodes:[]}}) as $ir
  | ($tests[0] // {tests:[]}) as $tests
  | [
      $tree.facts[]? | select(.from|not)
      | {id:sid(["symbol",.path,.line_start,.name]), kind:("symbol." + .kind), name, path, hash, confidence, evidence:{source:"tree_sitter_scan", parser, language}}
    ] as $symbols
  | [
      $ir.nodes[]?
      | {id:sid(["interface",.path,.line_start,.name]), kind:("interface." + .kind), name, path, hash:(.hash // (.signature|tostring)), confidence:(.confidence // 0.75), component:(.component // ""), evidence:{source:"semantic_interface_ir", parser:(.parser // "unknown")}}
    ] as $interfaces
  | [
      ($ir.dynamic_surfaces.nodes // [])[]?
      | {id:sid(["dynamic",.id]), kind:("dynamic." + (.kind // "surface")), name, path:(.path // ""), hash:(.hash // (.id|tostring)), confidence:(.confidence // 0.5), component:(.component // ""), evidence:{source:"dynamic_surface", risk_level:(.risk_level // "unknown"), verification_status:(.verification_status // "unknown")}}
    ] as $dynamic
  | [
      ($tests.tests // [])[]?
      | {id:sid(["test",.path]), kind:"test", name:(.path // ""), path:(.path // ""), hash:(.path // ""), confidence:0.8, evidence:{source:"test_graph"}}
    ] as $test_nodes
  | ($symbols + $interfaces + $dynamic + $test_nodes | unique_by(.id) | sort_by(.id)) as $nodes
  | [
      $tree.facts[]? | select(.from?)
      | {id:sid(["edge",.kind,.from,.to,.line]), kind:.kind, from:sid(["file",.from]), to:(.to|tostring), confidence:(.confidence // 0.7), evidence:{source:"tree_sitter_scan", path:.path, line:.line}}
    ] as $import_edges
  | [
      $interfaces[]? as $i
      | $symbols[]? as $s
      | select($i.path == $s.path and $i.name == $s.name)
      | {id:sid(["edge","symbol_exports_interface",$s.id,$i.id]), kind:"symbol_exports_interface", from:$s.id, to:$i.id, confidence:([$s.confidence,$i.confidence]|min), evidence:{source:"semantic_graph_join"}}
    ] as $interface_edges
  | [
      $dynamic[]? as $d
      | $symbols[]? as $s
      | select($d.path != "" and $d.path == $s.path)
      | {id:sid(["edge","file_owns_dynamic_surface",$s.id,$d.id]), kind:"file_owns_dynamic_surface", from:$s.id, to:$d.id, confidence:([$s.confidence,$d.confidence]|min), evidence:{source:"path_join"}}
    ] as $dynamic_edges
  | ($import_edges + $interface_edges + $dynamic_edges | unique_by(.id) | sort_by(.id)) as $edges
  | {
      schema_version:"2.0", ok:true, root:$root, struct:$struct, graph_hash:"pending",
      summary:{nodes:($nodes|length), edges:($edges|length), symbols:($symbols|length), interfaces:($interfaces|length), dynamic_surfaces:($dynamic|length), tests:($test_nodes|length), lsp_workspaces:(($lsp.workspaces // [])|length)},
      nodes:$nodes, edges:$edges,
      inputs:{tree_sitter:$tree.summary, lsp:$lsp.summary, semantic_ir:$ir.summary, tests:$tests.summary}
    }')
graph_hash=$(jq -c '{nodes:[.nodes[].id],edges:[.edges[].id]}' <<<"$report" | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $1}')
report=$(jq --arg graph_hash "$graph_hash" '.graph_hash=$graph_hash' <<<"$report")
printf '%s\n' "$report" > "$OUT"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Semantic Graph nodes=" + (.summary.nodes|tostring) + " edges=" + (.summary.edges|tostring)' <<<"$report"; fi
