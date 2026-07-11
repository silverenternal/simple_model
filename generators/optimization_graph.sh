#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="."
STRUCT="${STRUCT_FILE:-./struct.json}"
OUT="generated/optimization/graph.json"
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

command -v jq >/dev/null 2>&1 || { echo "[FAIL] missing jq" >&2; exit 2; }
[[ -d "$ROOT" && -f "$STRUCT" ]] || { echo "[FAIL] missing root or struct" >&2; exit 2; }
ROOT="$(cd "$ROOT" && pwd)"
STRUCT="$(cd "$(dirname "$STRUCT")" && pwd)/$(basename "$STRUCT")"
mkdir -p "$(dirname "$OUT")"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
bash "$SELF_DIR/semantic_interface_ir.sh" --root "$ROOT" --struct "$STRUCT" --output "$tmp/interface-ir.json" --json > "$tmp/ir.json" 2>/dev/null || jq -n '{nodes:[],dynamic_surfaces:{nodes:[],summary:{nodes:0}},summary:{nodes:0}}' > "$tmp/ir.json"
bash "$SELF_DIR/semantic_graph.sh" --root "$ROOT" --struct "$STRUCT" --output "$tmp/semantic-graph.json" --json > "$tmp/semantic.json" 2>/dev/null || jq -n '{nodes:[],edges:[],summary:{nodes:0}}' > "$tmp/semantic.json"
bash "$SELF_DIR/test_graph.sh" --root "$ROOT" --struct "$STRUCT" --json > "$tmp/tests.json" 2>/dev/null || jq -n '{tests:[],components:[],summary:{tests:0}}' > "$tmp/tests.json"
bash "$SELF_DIR/optimization_plan.sh" --root "$ROOT" --struct "$STRUCT" --output-dir "$tmp/opt" --json > "$tmp/plan.json" 2>/dev/null || jq -n '{actions:[],summary:{actions:0}}' > "$tmp/plan.json"
bash "$SELF_DIR/ownership_resolve.sh" --root "$ROOT" --struct "$STRUCT" --json > "$tmp/owners.json" 2>/dev/null || jq -n '{owners:[],summary:{owners:0}}' > "$tmp/owners.json"

report=$(jq -n \
  --arg root "$ROOT" \
  --arg struct "$STRUCT" \
  --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --slurpfile struct_file "$STRUCT" \
  --slurpfile ir_file "$tmp/ir.json" \
  --slurpfile semantic_file "$tmp/semantic.json" \
  --slurpfile tests_file "$tmp/tests.json" \
  --slurpfile plan_file "$tmp/plan.json" \
  --slurpfile owners_file "$tmp/owners.json" '
  def sid($parts): ($parts | join(":") | gsub("[^A-Za-z0-9_.:-]"; "_"));
  def h($x): ($x|tostring);
  ($struct_file[0]) as $s
  | ($ir_file[0] // {}) as $ir
  | ($semantic_file[0] // {}) as $semantic
  | ($tests_file[0] // {}) as $tests
  | ($plan_file[0] // {}) as $plan
  | ($owners_file[0] // {}) as $owners
  | [
      $s.modules[]? as $m
      | $m.components[]?
      | {id:sid(["component",$m.name,.name]), kind:"component", name:.name, module:$m.name, component:.name, path:(.path // ""), hash:h(.), score_weight:1, risk:(.risk // "medium"), evidence:{source:"struct", imports:(.imports // []), exports:(.exports // [])}}
    ] as $components
  | [
      ($semantic.nodes // [])[]?
      | select(.kind|startswith("symbol."))
      | {id:sid(["semantic",.id]), kind:"semantic_symbol", name:(.name // .id), module:"", component:(.component // ""), path:(.path // ""), hash:(.hash // h(.)), score_weight:0.7, risk:"low", evidence:{source:"semantic_graph_v2", confidence:(.confidence // 0), original_id:.id}}
    ] as $semantic_nodes
  | [
      $ir.nodes[]?
      | {id:sid(["interface",(.component // ""),.name,(.line_start // 0)]), kind:"interface", name:.name, module:(.module // ""), component:(.component // ""), path:(.path // ""), hash:h(.), score_weight:0.5, risk:"low", evidence:{source:"semantic_interface_ir", parser:(.parser // "unknown")}}
    ] as $interfaces
  | [
      ($ir.dynamic_surfaces.nodes // [])[]?
      | {id:sid(["dynamic",.id]), kind:"dynamic_surface", name:.name, module:(.module // ""), component:(.component // ""), path:(.path // ""), hash:(.hash // h(.)), score_weight:1.5, risk:(.risk_level // "dynamic_unverified"), evidence:{source:"dynamic_surface", kind:.kind, verification_status:(.verification_status // "unknown")}}
    ] as $dynamic
  | [
      ($tests.tests // [])[]?
      | {id:sid(["test",.path]), kind:"test", name:.path, path:.path, hash:h(.), score_weight:0.8, risk:"low", evidence:{source:"test_graph", kind:(.kind // "test")}}
    ] as $test_nodes
  | [
      ($plan.actions // [])[]?
      | {id:sid(["macro",.id]), kind:"macro_candidate", name:.macro_id, component:(.target.component // ""), path:(.target.path // ""), hash:h(.), score_weight:2, risk:(.risk // "medium"), evidence:{source:"optimization_plan", reason:(.reason // ""), writes:(.writes // [])}}
    ] as $macros
  | ($components + $semantic_nodes + $interfaces + $dynamic + $test_nodes + $macros) as $nodes
  | [
      $s.modules[]? as $m
      | $m.components[]? as $c
      | ($c.imports // [])[]?
      | {from:sid(["component",$m.name,$c.name]), to:sid(["component",($m.name),.]), kind:"declared_import", evidence:{source:"struct"}}
    ] as $import_edges_raw
  | [
      $interfaces[]? as $i
      | select(($i.component // "") != "")
      | {from:sid(["component",($i.module // ""),$i.component]), to:$i.id, kind:"exports_interface", evidence:{source:"semantic_interface_ir"}}
    ] as $interface_edges_raw
  | [
      $dynamic[]? as $d
      | select(($d.component // "") != "")
      | {from:sid(["component",($d.module // ""),$d.component]), to:$d.id, kind:"owns_dynamic_surface", evidence:{source:"dynamic_surface"}}
    ] as $dynamic_edges_raw
  | [
      $macros[]? as $m
      | select(($m.component // "") != "")
      | {from:$m.id, to:sid(["component",($components[]? | select(.component == $m.component) | .module),$m.component]), kind:"macro_targets", evidence:$m.evidence}
    ] as $macro_edges_raw
  | [
      ($semantic.edges // [])[]?
      | {from:sid(["semantic",.from]), to:sid(["semantic",.to]), kind:("semantic_" + (.kind // "edge")), evidence:{source:"semantic_graph_v2", confidence:(.confidence // 0)}}
    ] as $semantic_edges_raw
  | ($import_edges_raw + $semantic_edges_raw + $interface_edges_raw + $dynamic_edges_raw + $macro_edges_raw) as $edges_raw
  | [
      $edges_raw[]?
      | . + {id:sid(["edge",.kind,.from,.to]), hash:h(.)}
    ] | unique_by(.id) | sort_by(.id) as $edges
  | ($nodes | unique_by(.id) | sort_by(.id)) as $stable_nodes
  | {
      schema_version:"1.0",
      ok:true,
      generated_at:$generated_at,
      root:$root,
      struct:$struct,
      graph_hash:"pending",
      summary:{
        nodes:($stable_nodes|length),
        edges:($edges|length),
        components:($components|length),
        interfaces:($interfaces|length),
        dynamic_surfaces:($dynamic|length),
        tests:($test_nodes|length),
        macro_candidates:($macros|length)
      },
      nodes:$stable_nodes,
      edges:$edges,
      inputs:{semantic_graph:($semantic.summary // {}), semantic_ir:($ir.summary // {}), tests:($tests.summary // {}), plan:($plan.summary // {}), owners:($owners.summary // {})}
    }')
graph_hash=$(jq -c '{nodes:[.nodes[].id],edges:[.edges[].id]}' <<<"$report" | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $1}')
report=$(jq --arg graph_hash "$graph_hash" '.graph_hash=$graph_hash' <<<"$report")

printf '%s\n' "$report" > "$OUT"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Optimization Graph nodes=" + (.summary.nodes|tostring) + " edges=" + (.summary.edges|tostring)' <<<"$report"; fi
