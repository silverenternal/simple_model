#!/usr/bin/env bash
set -euo pipefail
ROOT="."
STRUCT="${STRUCT_FILE:-./struct.json}"
OUT_DIR="macros/families"
JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --struct|-s) STRUCT="$2"; shift 2 ;;
    --output-dir) OUT_DIR="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
mkdir -p "$OUT_DIR"
families=$(jq -n '[
  {id:"framework_route_adoption", schema_version:"1.0", parameters:["framework","route_kind","component_selector"], selectors:["semantic_ir.nodes[kind=route]"], invariants:["route nodes keep component ownership"], safety:{risk:"medium", fixture_required:true}},
  {id:"component_boundary_repair", schema_version:"1.0", parameters:["source_component","target_component","edge_kind"], selectors:["workspace_graph.components","import_graph.edges"], invariants:["no undeclared write outside struct or selected package"], safety:{risk:"medium", fixture_required:true}}
]')
jq -c '.[]' <<<"$families" | while read -r f; do printf '%s\n' "$f" > "$OUT_DIR/$(jq -r '.id' <<<"$f").json"; done
report=$(jq -n --arg root "$ROOT" --arg struct "$STRUCT" --arg output_dir "$OUT_DIR" --argjson families "$families" '{schema_version:"1.0", ok:true, root:$root, struct:$struct, output_dir:$output_dir, summary:{families:($families|length)}, families:$families}')
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Macro Families generated=" + (.summary.families|tostring)' <<<"$report"; fi
