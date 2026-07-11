#!/usr/bin/env bash
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="."
STRUCT="${STRUCT_FILE:-./struct.json}"
WORKFLOW="optimize"
OUT_DIR="generated/codex/context-packs"
JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --struct|-s) STRUCT="$2"; shift 2 ;;
    --workflow) WORKFLOW="$2"; shift 2 ;;
    --output-dir) OUT_DIR="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
mkdir -p "$OUT_DIR"
ROOT="$(cd "$ROOT" && pwd)"
ir=$(bash "$SELF_DIR/semantic_interface_ir.sh" --root "$ROOT" --struct "$STRUCT" --json || jq -n '{nodes:[],summary:{nodes:0}}')
score=$(bash "$SELF_DIR/optimization_score.sh" --root "$ROOT" --struct "$STRUCT" --json || jq -n '{score:0,factors:{}}')
policy=$(bash "$SELF_DIR/policy_eval.sh" --json 2>/dev/null || jq -n '{decision:"allow"}')
dynamic=$(bash "$SELF_DIR/dynamic_surface_scan.sh" --root "$ROOT" --struct "$STRUCT" --json || jq -n '{nodes:[],summary:{nodes:0},probe_recommendations:[]}')
policy=$(bash "$SELF_DIR/policy_eval.sh" --dynamic <(printf "%s" "$dynamic") --json 2>/dev/null || jq -n '{decision:"allow"}')
pack=$(jq -n --arg workflow "$WORKFLOW" --arg root "$ROOT" --arg struct "$STRUCT" --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson ir "$ir" --argjson score "$score" --argjson policy "$policy" --argjson dynamic "$dynamic" '{
  schema_version:"1.0", ok:true, workflow:$workflow, root:$root, struct:$struct, generated_at:$generated_at,
  budget:{max_nodes:200, omitted_reason:"large arrays are trimmed by deterministic priority"},
  graph_slice:{summary:$ir.summary, nodes:($ir.nodes|sort_by(.kind,.component,.name)|.[0:200])},
  dynamic_evidence:{summary:$dynamic.summary, nodes:($dynamic.nodes|sort_by(.risk_level,.path,.line)|.[0:200]), probe_recommendations:$dynamic.probe_recommendations},
  score:$score,
  policy:$policy,
  allowed_macros:["split_struct_include","normalize_component_exports","sync_struct_imports_from_code_facts"],
  forbidden_macro_actions:($dynamic.nodes | map(select(.risk_level=="dynamic_unsafe" or .verification_status!="observed")) | map({surface_id:.id, reason:"requires runtime observation or waiver before automated apply"})),
  commands:["simple_model_pi.sh doctor --json","simple_model_pi.sh optimize --dry-run --json","simple_model_pi.sh pr-gate --json"],
  omitted:{nodes:((($ir.nodes|length) - 200) as $n | if $n > 0 then $n else 0 end), dynamic_nodes:((($dynamic.nodes|length) - 200) as $n | if $n > 0 then $n else 0 end), dynamic_risks:($dynamic.nodes|map(select(.risk_level=="dynamic_unsafe" or .verification_status!="observed"))|length)}
}')
printf '%s\n' "$pack" > "$OUT_DIR/$WORKFLOW.json"
{ echo "# Codex Context Pack: $WORKFLOW"; echo; jq -r '"- nodes: " + (.graph_slice.summary.nodes|tostring), "- score: " + (.score.score|tostring), "- policy: " + .policy.decision' <<<"$pack"; } > "$OUT_DIR/$WORKFLOW.md"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$pack"; else echo "$OUT_DIR/$WORKFLOW.json"; fi
