#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="."
STRUCT=""
OUT_DIR="generated/adoption"
JSON_OUT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --struct|-s) STRUCT="$2"; shift 2 ;;
    --output-dir|-o) OUT_DIR="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

ROOT="$(cd "$ROOT" && pwd)"
if [[ -z "$STRUCT" ]]; then STRUCT="$ROOT/struct.json"; fi
STRUCT="$(cd "$(dirname "$STRUCT")" && pwd)/$(basename "$STRUCT")"
mkdir -p "$OUT_DIR"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

bash "$SELF_DIR/external_repo_eval.sh" --root "$ROOT" --struct "$STRUCT" --output "$tmp/eval.json" --json >/dev/null
bash "$SELF_DIR/confidence_optimizer.sh" --root "$ROOT" --struct "$STRUCT" --output "$tmp/confidence.json" --json >/dev/null
bash "$SELF_DIR/macro_drill.sh" --root "$ROOT" --output "$tmp/drill.json" --json >/dev/null

cockpit=$(jq -n --arg root "$ROOT" --arg struct "$STRUCT" --slurpfile eval "$tmp/eval.json" --slurpfile confidence "$tmp/confidence.json" --slurpfile drill "$tmp/drill.json" '{
  schema_version:"1.0", ok:true, root:$root, struct:$struct,
  readiness:{
    parser_coverage:($eval[0].summary.parser_files // 0),
    parser_low_confidence:($eval[0].summary.parser_low_confidence // 0),
    graph_confidence:{nodes:($eval[0].summary.graph_nodes // 0), edges:($eval[0].summary.graph_edges // 0)},
    macro_safety:{safe_now:($confidence[0].summary.safe_now // 0), review_first:($confidence[0].summary.review_first // 0), drill_ok:($drill[0].ok // false)},
    cache:{status:"content-addressed", warm_runtime_estimate:($eval[0].summary.warm_runtime_seconds_estimate // 0)}
  },
  queues:$confidence[0].queues,
  top_actions:($eval[0].top_actions | map(select(.condition)) | .[:3]),
  artifacts:{eval:$eval[0], confidence_plan:$confidence[0], macro_drill:$drill[0]}
}')

printf '%s\n' "$cockpit" > "$OUT_DIR/cockpit.json"
jq -r '
  "# simple_model Adoption Cockpit",
  "",
  "- readiness: " + (if .ok then "ok" else "blocked" end),
  "- parser files: " + (.readiness.parser_coverage|tostring),
  "- low-confidence parser files: " + (.readiness.parser_low_confidence|tostring),
  "- graph nodes: " + (.readiness.graph_confidence.nodes|tostring),
  "- graph edges: " + (.readiness.graph_confidence.edges|tostring),
  "- safe-now macros: " + (.readiness.macro_safety.safe_now|tostring),
  "- review-first macros: " + (.readiness.macro_safety.review_first|tostring),
  "- macro drill ok: " + (.readiness.macro_safety.drill_ok|tostring),
  "",
  "## Top Actions",
  (.top_actions[]? | "- " + .action)
' "$OUT_DIR/cockpit.json" > "$OUT_DIR/cockpit.md"

{
  printf '%s\n' '<!doctype html><meta charset="utf-8"><title>simple_model Adoption Cockpit</title><style>body{font-family:system-ui;margin:32px;line-height:1.45}code,pre{background:#f6f8fa;padding:2px 4px;border-radius:4px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:12px}.card{border:1px solid #ddd;border-radius:6px;padding:12px}</style>'
  printf '%s\n' '<h1>simple_model Adoption Cockpit</h1><div class="grid">'
  jq -r '.readiness | to_entries[] | "<div class=\"card\"><strong>" + .key + "</strong><pre>" + (.value|tojson) + "</pre></div>"' "$OUT_DIR/cockpit.json"
  printf '%s\n' '</div><h2>Top Actions</h2><ul>'
  jq -r '.top_actions[]? | "<li>" + .action + "</li>"' "$OUT_DIR/cockpit.json"
  printf '%s\n' '</ul>'
} > "$OUT_DIR/cockpit.html"

if [[ "$JSON_OUT" == "1" ]]; then
  cat "$OUT_DIR/cockpit.json"
else
  jq -r '"Adoption Cockpit: safe_now=" + (.readiness.macro_safety.safe_now|tostring) + " review_first=" + (.readiness.macro_safety.review_first|tostring) + " report='"$OUT_DIR/cockpit.md"'"' "$OUT_DIR/cockpit.json"
fi
