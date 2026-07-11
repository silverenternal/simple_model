#!/usr/bin/env bash
set -euo pipefail

MOTIFS=""
OUT="generated/macros/templates.json"
JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --motifs) MOTIFS="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
mkdir -p "$(dirname "$OUT")"
if [[ -z "$MOTIFS" || ! -f "$MOTIFS" ]]; then
  MOTIFS="$(mktemp)"; trap 'rm -f "$MOTIFS"' EXIT
  jq -n '{candidates:[{id:"motif:boundary",motif:"boundary_drift",family:"boundary-repair",confidence:0.8,graph_path:["a","b"],missing_proof:["drill"]}]}' > "$MOTIFS"
fi
report=$(jq -n --slurpfile motifs "$MOTIFS" '
  ($motifs[0].candidates // []) as $c
  | ($c | group_by(.family) | map({
      id:("template." + (.[0].family // "unknown")),
      family:(.[0].family // "unknown"),
      status:"review_only",
      parameters:["selector","write_scope","test_selector"],
      selector_schema:{source:"semantic_graph_motif", motifs:(map(.motif)|unique|sort)},
      adapter_requirements:["codemod_backend_v2","formatter_policy","rollback_hashes"],
      fixtures_required:(map(.motif)|unique|map("fixture:" + .)),
      expected_score_delta:([.[].confidence] | add / length * 0.1),
      promotion_criteria:{operator_ir:true, preconditions:true, macro_drill:true, false_safe_apply:0, affected_test_recall:0.95},
      source_motifs:(map(.id)|sort),
      apply_capable:false,
      missing_evidence:(map(.missing_proof[]?)|unique|sort)
    }) | sort_by(.id)) as $templates
  | {
      schema_version:"1.0", ok:true,
      summary:{templates:($templates|length), apply_capable:0, review_only:($templates|length)},
      templates:$templates,
      policy:{review_only_until_promoted:true, dedupe_by_family:true}
    }')
printf '%s\n' "$report" > "$OUT"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Macro templates=" + (.summary.templates|tostring)' <<<"$report"; fi
