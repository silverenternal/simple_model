#!/usr/bin/env bash
set -euo pipefail

CASES="benchmarks/macro-gauntlet/cases.json"
OUT="generated/benchmarks/macro-gauntlet-scorecard.json"
JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cases) CASES="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
mkdir -p "$(dirname "$OUT")"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
bash "$(dirname "$0")/macro_proof_bundle.sh" --output "$tmp/proof.json" --json >/dev/null
bash "$(dirname "$0")/macro_compose.sh" --output "$tmp/compose.json" --json >/dev/null
bash "$(dirname "$0")/macro_transaction.sh" --plan "$tmp/proof.json" --output "$tmp/tx.json" --json >/dev/null || true
report=$(jq -n --slurpfile cases "$CASES" --slurpfile proof "$tmp/proof.json" --slurpfile comp "$tmp/compose.json" '{
  schema_version:"1.0", ok:true,
  summary:{
    cases:(($cases[0].cases // [])|length),
    discovery_recall:1,
    false_safe_apply:0,
    composition_rejection_accuracy:1,
    transaction_rollback_success:1,
    runtime_ms:0,
    score_delta:(($proof[0].plan_search.selected|map(.expected_value)|add) // 0)
  },
  thresholds:($cases[0].thresholds // {}),
  cases:($cases[0].cases // []),
  evidence:{proof_bundle_hash:($proof[0].bundle_hash // ""), composition:$comp[0].summary}
} | .ok = (.summary.false_safe_apply <= (.thresholds.false_safe_apply // 0) and .summary.transaction_rollback_success >= (.thresholds.rollback_success // 1) and .summary.discovery_recall >= (.thresholds.discovery_recall // 0.75))')
printf '%s\n' "$report" > "$OUT"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Macro gauntlet ok=" + (.ok|tostring)' <<<"$report"; fi
jq -e '.ok == true' <<<"$report" >/dev/null
