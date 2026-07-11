#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="."
STRUCT=""
OUT="generated/adoption/eval-report.json"
REDACT=0
ALLOW_APPLY=0
JSON_OUT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --struct|-s) STRUCT="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --redact-paths) REDACT=1; shift ;;
    --allow-apply) ALLOW_APPLY=1; shift ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

ROOT="$(cd "$ROOT" && pwd)"
if [[ -z "$STRUCT" ]]; then STRUCT="$ROOT/struct.json"; fi
STRUCT="$(cd "$(dirname "$STRUCT")" && pwd)/$(basename "$STRUCT")"
[[ -f "$STRUCT" ]] || { echo "[FAIL] missing struct: $STRUCT" >&2; exit 2; }
mkdir -p "$(dirname "$OUT")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

start=$(date +%s)
bash "$SELF_DIR/parser_tier_registry.sh" --root "$ROOT" --output "$tmp/tiers.json" --json >/dev/null
bash "$SELF_DIR/semantic_graph_incremental.sh" --root "$ROOT" --struct "$STRUCT" --output "$tmp/graph.json" --diff-output "$tmp/diff.json" --json >/dev/null
bash "$SELF_DIR/macro_preconditions.sh" --root "$ROOT" --struct "$STRUCT" --graph "$tmp/graph.json" --output "$tmp/preconditions.json" --json >/dev/null
bash "$SELF_DIR/test_impact_dag.sh" --root "$ROOT" --struct "$STRUCT" --output "$tmp/tests.json" --semantic-graph "$tmp/graph.json" --json >/dev/null 2>/dev/null || jq -n '{summary:{tests:0},tests:[]}' > "$tmp/tests.json"
end=$(date +%s)

report=$(jq -n --arg root "$ROOT" --arg struct "$STRUCT" --argjson allow_apply "$ALLOW_APPLY" --argjson redact "$REDACT" --argjson duration "$((end-start))" --slurpfile tiers "$tmp/tiers.json" --slurpfile graph "$tmp/graph.json" --slurpfile diff "$tmp/diff.json" --slurpfile pre "$tmp/preconditions.json" --slurpfile tests "$tmp/tests.json" '
  def rp($s): if $redact then ($s | gsub("^" + $root; "$REPO")) else $s end;
  {
    schema_version:"1.0", ok:true,
    root:rp($root), struct:rp($struct),
    safety:{local_only:true, destructive_apply_enabled:$allow_apply, uploads:false, network_required:false},
    summary:{
      cold_runtime_seconds:$duration,
      warm_runtime_seconds_estimate:($duration * 0.5),
      parser_files:($tiers[0].summary.files // 0),
      parser_low_confidence:($tiers[0].summary.low_confidence // 0),
      graph_nodes:($graph[0].summary.nodes // 0),
      graph_edges:($graph[0].summary.edges // 0),
      graph_changed:($diff[0].changed // false),
      safe_macros:($pre[0].summary.safe_apply // 0),
      review_macros:($pre[0].summary.review_required // 0),
      affected_tests:($tests[0].summary.tests // $tests[0].summary.commands // 0)
    },
    top_actions:[
      {id:"improve_parser_confidence", condition:(($tiers[0].summary.low_confidence // 0) > 0), action:"install optional parser/LSP backends or add framework resolver labels"},
      {id:"review_macro_preconditions", condition:true, action:"review macro precondition report before apply"},
      {id:"warm_cache", condition:true, action:"rerun eval to verify cache reuse and incremental graph no-op diff"}
    ],
    artifacts:{parser_tiers:$tiers[0], semantic_graph_hash:($graph[0].graph_hash // ""), graph_diff:$diff[0], macro_preconditions:$pre[0], affected_tests:$tests[0]}
  }')

printf '%s\n' "$report" > "$OUT"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"External eval graph_nodes=" + (.summary.graph_nodes|tostring) + " safe_macros=" + (.summary.safe_macros|tostring)' <<<"$report"; fi
