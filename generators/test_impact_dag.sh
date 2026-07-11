#!/usr/bin/env bash
set -euo pipefail

ROOT="."
STRUCT="${STRUCT_FILE:-./struct.json}"
OUT="generated/tests/test-impact-dag.json"
SEMANTIC=""
JSON_OUT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --struct|-s) STRUCT="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --semantic-graph) SEMANTIC="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

ROOT="$(cd "$ROOT" && pwd)"
[[ -f "$STRUCT" ]] || { echo "[FAIL] struct not found: $STRUCT" >&2; exit 2; }
mkdir -p "$(dirname "$OUT")"

test_files=$(find "$ROOT/tests" -maxdepth 1 -type f -name 'test_*.sh' 2>/dev/null | sort | sed "s#^$ROOT/##" | jq -R -s 'split("\n")[:-1]')
if [[ -z "$SEMANTIC" ]]; then
  SEMANTIC="$(dirname "$OUT")/semantic-graph.json"
  bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/semantic_graph.sh" --root "$ROOT" --struct "$STRUCT" --output "$SEMANTIC" --json >/dev/null 2>&1 || true
fi
semantic_json='{"nodes":[],"edges":[],"summary":{}}'
[[ -f "$SEMANTIC" ]] && semantic_json=$(jq . "$SEMANTIC")
report=$(jq -n --arg root "$ROOT" --arg struct "$STRUCT" --argjson tests "$test_files" --argjson semantic "$semantic_json" '
  def domain($p):
    if $p|test("dynamic") then "dynamic"
    elif $p|test("plugin") then "plugin"
    elif $p|test("macro|v07") then "optimizer"
    elif $p|test("v04|v05") then "adoption"
    elif $p|test("benchmark") then "benchmark"
    else "core" end;
  def inputs($p):
    (["struct.json","todo.json","specs/"] +
    (if domain($p)=="dynamic" then ["examples/dynamic-case-study/","generators/dynamic_","generators/runtime_probe.sh"] else [] end) +
    (if domain($p)=="plugin" then ["plugins/","codex/skills/","tools/simple_model_mcp.sh","tools/package_codex_plugin.sh"] else [] end) +
    (if domain($p)=="benchmark" then ["benchmarks/","generators/benchmark_scorecard.sh","generators/release_slo.sh"] else [] end) +
    (if domain($p)=="optimizer" then ["macros/","generators/macro_","generators/optimization_"] else [] end));
  ($tests | map({
    id:(. | split("/")[-1] | sub("\\.sh$"; "")),
    path:.,
    command:("bash " + .),
    domain:domain(.),
    inputs:inputs(.),
    semantic_selectors:($semantic.nodes | map(select((.kind|test("dynamic|interface|symbol")) and (.path|length)>0) | {node_id:.id,path:.path,kind:.kind}) | .[0:50]),
    explain:{strategy:"semantic-graph-domain-hybrid", fallback:"full when no graph evidence", graph_nodes:($semantic.summary.nodes // 0)},
    outputs:[],
    deps:[],
    timeout:120,
    resource:(if domain(.)=="benchmark" then "cpu-heavy" else "default" end),
    cache:true,
    conflicts:(if domain(.)=="plugin" then ["dist/","generated/plugin-self-audit/"] else [] end)
  })) as $nodes
  | {
      schema_version:"1.0",
      ok:true,
      root:$root,
      struct:$struct,
      summary:{tests:($nodes|length), domains:($nodes|map(.domain)|unique|length), semantic_nodes:($semantic.summary.nodes // 0)},
      tests:$nodes,
      selection_rules:{
        fast:["adoption"],
        dynamic:["dynamic"],
        plugin:["plugin"],
        benchmark:["benchmark"],
        full:["core","adoption","optimizer","dynamic","plugin","benchmark"]
      }
    }')

printf '%s\n' "$report" > "$OUT"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Test Impact DAG tests=" + (.summary.tests|tostring)' <<<"$report"; fi
