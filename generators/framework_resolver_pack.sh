#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="resolvers/frameworks"
JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir) OUT_DIR="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
mkdir -p "$OUT_DIR"
frameworks=(nextjs nestjs express fastify fastapi django rails spring worker-queues openapi grpc terraform kubernetes package-plugins)
for fw in "${frameworks[@]}"; do
  jq -n --arg id "$fw" '{
    schema_version:"1.0", id:$id,
    patterns:["routes","dependency_injection","event_subscriptions","plugin_registration","env_gated_behavior","generated_artifacts"],
    ast_sources:["tree_sitter_scan","semantic_graph_v2"],
    dynamic_evidence:["runtime_contract","dynamic_surface_ir"],
    expected_tests:["framework_resolver","dynamic_policy","affected_tests"],
    safety:{network_required:false,secrets_required:false,fail_closed:true}
  }' > "$OUT_DIR/$fw.json"
done
report=$(jq -n --arg out "$OUT_DIR" --argjson count "${#frameworks[@]}" '{schema_version:"1.0", ok:true, output_dir:$out, summary:{frameworks:$count}}')
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Framework resolvers=" + (.summary.frameworks|tostring)' <<<"$report"; fi
