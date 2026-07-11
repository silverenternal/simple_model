#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="."
STRUCT="${STRUCT_FILE:-./struct.json}"
OUT="generated/intelligence/interface-ir.json"
JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --struct|-s) STRUCT="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    -h|--help) echo "semantic_interface_ir.sh --root <repo> --struct <struct> [--json]"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
command -v jq >/dev/null 2>&1 || { echo "[FAIL] missing jq" >&2; exit 2; }
[[ -d "$ROOT" && -f "$STRUCT" ]] || { echo "[FAIL] missing root or struct" >&2; exit 2; }
ROOT="$(cd "$ROOT" && pwd)"
STRUCT="$(cd "$(dirname "$STRUCT")" && pwd)/$(basename "$STRUCT")"
mkdir -p "$(dirname "$OUT")"

interfaces=$(bash "$SELF_DIR/interface_scan.sh" --root "$ROOT" --struct "$STRUCT" --json || true)
framework=$(bash "$SELF_DIR/framework_surfaces.sh" --root "$ROOT" --struct "$STRUCT" --json 2>/dev/null || jq -n '{surfaces:[]}')
contracts=$(bash "$SELF_DIR/contract_graph.sh" --root "$ROOT" --struct "$STRUCT" --json 2>/dev/null || jq -n '{contracts:[]}')
dynamic_file="$(mktemp)"
trap 'rm -f "$dynamic_file"' EXIT
bash "$SELF_DIR/dynamic_surface_scan.sh" --root "$ROOT" --struct "$STRUCT" --json > "$dynamic_file" 2>/dev/null || jq -n '{nodes:[],summary:{nodes:0}}' > "$dynamic_file"

report=$(jq -n \
  --arg root "$ROOT" \
  --arg struct "$STRUCT" \
  --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson interfaces "$interfaces" \
  --argjson framework "$framework" \
  --argjson contracts "$contracts" \
  --slurpfile dynamic_file "$dynamic_file" '
  ($dynamic_file[0] // {nodes:[],summary:{nodes:0}}) as $dynamic
  |
  def sid($parts): ($parts | join(":") | gsub("[^A-Za-z0-9_.:-]"; "_"));
  [
    $interfaces.components[]? as $c
    | $c.interfaces[]?
    | {
        id:sid(["symbol", $c.module, $c.component, .name, (.line|tostring)]),
        kind:(.kind // "symbol"),
        name:.name,
        visibility:(.visibility // "public"),
        signature:(.signature // .name),
        path:(.path // $c.path),
        line_start:(.line // 0),
        line_end:(.line // 0),
        module:$c.module,
        component:$c.component,
        parser:(.parser // "unknown"),
        confidence:(if ((.parser // "") | test("regex")) then 0.55 else 0.90 end),
        hash:(.hash // ""),
        contract_refs:[],
        evidence:{source:"interface_scan", declared_exports:$c.declared_exports, discovered_exports:$c.discovered_exports}
      }
  ] as $symbols
  | [
      $framework.surfaces[]? | {
        id:sid(["route", .method, .path, (.component // "unknown")]),
        kind:"route",
        name:((.method // "ANY") + " " + (.path // "")),
        visibility:"public",
        signature:((.method // "ANY") + " " + (.path // "")),
        path:(.file // .path // ""),
        line_start:(.line // 0),
        line_end:(.line // 0),
        module:(.module // ""),
        component:(.component // ""),
        parser:(.parser // "framework_surface_extractor"),
        confidence:(.confidence // 0.75),
        hash:(.hash // ""),
        contract_refs:[],
        evidence:{source:"framework_surfaces", framework:(.framework // ""), handler:(.handler // "")}
      }
    ] as $routes
  | [
      $contracts.contracts[]? | {
        id:sid(["contract", .kind, .name]),
        kind:("contract." + (.kind // "unknown")),
        name:(.name // .path // "contract"),
        visibility:"public",
        signature:(.signature // .name // .path // "contract"),
        path:(.path // ""),
        line_start:0,
        line_end:0,
        module:(.module // ""),
        component:(.component // ""),
        parser:(.parser // "contract_graph"),
        confidence:(.confidence // 0.80),
        hash:(.hash // ""),
        contract_refs:[.id // .name // .path],
        evidence:{source:"contract_graph", diff_class:(.diff_class // "unknown")}
      }
    ] as $contract_nodes
  | ($symbols + $routes + $contract_nodes) as $nodes
  | {
      schema_version:"2.0",
      ok:true,
      generated_at:$generated_at,
      root:$root,
      struct:$struct,
      summary:{
        nodes:($nodes|length),
        symbols:($symbols|length),
        routes:($routes|length),
        contracts:($contract_nodes|length),
        dynamic_surfaces:(($dynamic.nodes // [])|length),
        events:($nodes|map(select(.kind=="event"))|length),
        jobs:($nodes|map(select(.kind=="job"))|length),
        configs:($nodes|map(select(.kind=="config"))|length)
      },
      nodes:$nodes,
      dynamic_surfaces:{
        summary:($dynamic.summary // {nodes:0}),
        nodes:(($dynamic.nodes // []) | map(. as $dn | {
          id, kind, name, path, line, module, component, resolver, confidence,
          risk_level, verification_status, evidence, hash,
          linked_static_nodes:($nodes | map(select(.path == ($dn.path // "") or .component == ($dn.component // "")) | .id))
        }))
      }
    }')
printf '%s\n' "$report" > "$OUT"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Semantic Interface IR nodes=" + (.summary.nodes|tostring) + " output='"$OUT"'"' <<<"$report"; fi
