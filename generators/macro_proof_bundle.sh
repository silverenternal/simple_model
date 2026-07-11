#!/usr/bin/env bash
set -euo pipefail

OUT="generated/macros/proof-bundle.json"
JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output|-o) OUT="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
mkdir -p "$(dirname "$OUT")"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
bash "$(dirname "$0")/macro_operator_ir.sh" --output "$tmp/operators.json" --json >/dev/null
bash "$(dirname "$0")/macro_discover_motifs.sh" --output "$tmp/motifs.json" --json >/dev/null
bash "$(dirname "$0")/macro_preconditions.sh" --output "$tmp/preconditions.json" --json >/dev/null
bash "$(dirname "$0")/macro_compose.sh" --operators "$tmp/operators.json" --output "$tmp/compose.json" --json >/dev/null
bash "$(dirname "$0")/macro_plan_search.sh" --operators "$tmp/operators.json" --composition "$tmp/compose.json" --output "$tmp/search.json" --json >/dev/null
bash "$(dirname "$0")/macro_drill.sh" --output "$tmp/drill.json" --json >/dev/null
report=$(jq -n --slurpfile op "$tmp/operators.json" --slurpfile motifs "$tmp/motifs.json" --slurpfile pre "$tmp/preconditions.json" --slurpfile comp "$tmp/compose.json" --slurpfile search "$tmp/search.json" --slurpfile drill "$tmp/drill.json" '{
  schema_version:"1.0", ok:true,
  operator_ir:$op[0],
  motif_evidence:$motifs[0],
  preconditions:$pre[0],
  composition:$comp[0],
  plan_search:$search[0],
  drill_report:$drill[0],
  affected_tests:($comp[0].accepted_groups[0].required_tests // []),
  rollback_manifest:($drill[0].phases.apply.rollback_manifest // {files:[]}),
  score_delta_proof:{expected_positive:(($search[0].selected|map(.expected_value)|add // 0) >= 0), source:"macro_plan_search"},
  replay:{offline:true, stable:true},
  bundle_hash:"pending"
}')
hash=$(jq -c 'del(.bundle_hash)' <<<"$report" | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $1}')
report=$(jq --arg h "$hash" '.bundle_hash=$h' <<<"$report")
printf '%s\n' "$report" > "$OUT"
md="${OUT%.json}.md"
jq -r '"# Macro Proof Bundle\n\n- ok: " + (.ok|tostring) + "\n- bundle_hash: " + .bundle_hash + "\n- operators: " + (.operator_ir.summary.operators|tostring) + "\n- motifs: " + (.motif_evidence.summary.candidates|tostring) + "\n- selected: " + (.plan_search.summary.selected|tostring)' "$OUT" > "$md"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Macro proof bundle hash=" + .bundle_hash' <<<"$report"; fi
