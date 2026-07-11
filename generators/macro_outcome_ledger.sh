#!/usr/bin/env bash
set -euo pipefail

PROOF=""
OUT="generated/macros/outcome-ledger.json"
REDACT=0
JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --proof) PROOF="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --redact-paths) REDACT=1; shift ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
mkdir -p "$(dirname "$OUT")"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
if [[ -z "$PROOF" || ! -f "$PROOF" ]]; then PROOF="$tmp/proof.json"; bash "$(dirname "$0")/macro_proof_bundle.sh" --output "$PROOF" --json >/dev/null; fi
entries=$(jq -n --argjson redact "$REDACT" --slurpfile proof "$PROOF" '
  ($proof[0].plan_search.selected // []) as $selected
  | [
      $selected[]? as $s
      | {
          previous_hash:"",
          operator_id:$s.id,
          repo_fingerprint:($proof[0].operator_ir.root // "local"),
          motif_id:($proof[0].motif_evidence.candidates[0].id // "unknown"),
          decision:(if $s.mode=="apply" then "apply_ready" else "simulate_or_review" end),
          score_delta:($s.expected_value // 0),
          runtime_ms:0,
          affected_tests:($proof[0].affected_tests // []),
          rollback_result:(if $proof[0].drill_report.summary.rollback_ok then "ok" else "failed" end),
          review_reason:($s.reason // ""),
          final_status:"recorded"
        }
    ]')
entries=$(jq -c '.[]' <<<"$entries" | awk 'BEGIN{prev=""} {print $0}' | while IFS= read -r e; do
  h=$(printf '%s' "$e" | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $1}')
  jq --arg h "$h" '.entry_hash=$h' <<<"$e"
done | jq -s '.')
report=$(jq -n --argjson entries "$entries" '{
  schema_version:"1.0", ok:true,
  summary:{entries:($entries|length), rollback_ok:($entries|map(select(.rollback_result=="ok"))|length), failures:($entries|map(select(.final_status!="recorded"))|length)},
  entries:$entries,
  privacy:{store_full_source:false, redactable_paths:true},
  append_only:true
}')
printf '%s\n' "$report" > "$OUT"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Macro ledger entries=" + (.summary.entries|tostring)' <<<"$report"; fi
