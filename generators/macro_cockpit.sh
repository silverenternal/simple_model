#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="generated/macros"
JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir|-o) OUT_DIR="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
mkdir -p "$OUT_DIR"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
if [[ -f generated/macros/motif-candidates.json ]]; then
  cp generated/macros/motif-candidates.json "$tmp/motifs.json"
else
  bash "$(dirname "$0")/macro_discover_motifs.sh" --output "$tmp/motifs.json" --json >/dev/null
fi
bash "$(dirname "$0")/macro_template_synth.sh" --motifs "$tmp/motifs.json" --output "$tmp/templates.json" --json >/dev/null
bash "$(dirname "$0")/macro_proof_bundle.sh" --output "$tmp/proof.json" --json >/dev/null
bash "$(dirname "$0")/macro_outcome_ledger.sh" --proof "$tmp/proof.json" --output "$tmp/ledger.json" --json >/dev/null
bash "$(dirname "$0")/macro_family_ranker.sh" --ledger "$tmp/ledger.json" --output "$tmp/rankings.json" --json >/dev/null
bash "$(dirname "$0")/macro_promotion_gate.sh" --templates "$tmp/templates.json" --proof "$tmp/proof.json" --rankings "$tmp/rankings.json" --output "$tmp/promotion.json" --json >/dev/null
report=$(jq -n --slurpfile motifs "$tmp/motifs.json" --slurpfile templates "$tmp/templates.json" --slurpfile proof "$tmp/proof.json" --slurpfile ledger "$tmp/ledger.json" --slurpfile rankings "$tmp/rankings.json" --slurpfile promotion "$tmp/promotion.json" '{
  schema_version:"1.0", ok:true,
  summary:{
    motifs:($motifs[0].summary.candidates // 0),
    templates:($templates[0].summary.templates // 0),
    safe_plans:($proof[0].plan_search.summary.selected // 0),
    blocked_plans:($proof[0].preconditions.summary.evidence_missing // 0),
    proof_bundle_hash:($proof[0].bundle_hash // ""),
    ranked_families:($rankings[0].summary.families // 0),
    promoted:($promotion[0].summary.promoted // 0)
  },
  top_safe_actions:($proof[0].plan_search.selected // [] | .[:3]),
  top_review_actions:($motifs[0].candidates // [] | map(select(.action=="review-first")) | .[:3]),
  top_evidence_gaps:($motifs[0].candidates // [] | map(select(.action=="gather-evidence")) | .[:3]),
  retired_or_review_only:($rankings[0].families // [] | map(select(.recommendation!="keep_or_promote"))),
  artifacts:{motifs:$motifs[0], templates:$templates[0], proof:$proof[0], ledger:$ledger[0], rankings:$rankings[0], promotion:$promotion[0]}
}')
printf '%s\n' "$report" > "$OUT_DIR/cockpit.json"
jq -r '"# Macro Cockpit\n\n- motifs: " + (.summary.motifs|tostring) + "\n- templates: " + (.summary.templates|tostring) + "\n- safe plans: " + (.summary.safe_plans|tostring) + "\n- proof bundle: " + .summary.proof_bundle_hash + "\n- promoted: " + (.summary.promoted|tostring)' "$OUT_DIR/cockpit.json" > "$OUT_DIR/cockpit.md"
{
  printf '%s\n' '<!doctype html><meta charset="utf-8"><title>Macro Cockpit</title><style>body{font-family:system-ui;margin:32px}.card{border:1px solid #ddd;border-radius:6px;padding:12px;margin:8px 0}pre{background:#f6f8fa;padding:8px;overflow:auto}</style><h1>Macro Cockpit</h1>'
  jq -r '.summary | to_entries[] | "<div class=\"card\"><strong>" + .key + "</strong><pre>" + (.value|tojson) + "</pre></div>"' "$OUT_DIR/cockpit.json"
} > "$OUT_DIR/cockpit.html"
if [[ "$JSON_OUT" == "1" ]]; then cat "$OUT_DIR/cockpit.json"; else jq -r '"Macro cockpit motifs=" + (.summary.motifs|tostring)' "$OUT_DIR/cockpit.json"; fi
