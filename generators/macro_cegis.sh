#!/usr/bin/env bash
set -euo pipefail
INPUT=""; OUT="generated/macros/counterexample-ledger.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in --input|-i) INPUT="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac
done
[[ -f "$INPUT" ]] || { echo "--input is required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
macro_id="$(jq -r '.macro_id // .macro.id // "unknown"' "$INPUT")"; matcher_before="$(jq -c '.matcher_before // {}' "$INPUT")"; cex_count="$(jq '.counterexamples|length' "$INPUT")"
entries="$tmp/entries.jsonl"; : > "$entries"
jq -c '.counterexamples[]' "$INPUT" | while IFS= read -r cex; do
  jq -n --arg macro_id "$macro_id" --argjson cex "$cex" '{schema_version:"1.0",macro_id:$macro_id,proof_obligation:($cex.proof_obligation//"unknown"),input:$cex.input,expected:$cex.expected,observed:$cex.observed,resolved:($cex.resolved//false),regression_fixture:true}' > "$tmp/one.json"
  bash "$(dirname "$0")/counterexample_minimize.sh" --input "$tmp/one.json" --output "$tmp/min.json" --json >/dev/null
  cat "$tmp/min.json" >> "$entries"
done
ledger="$(jq -s '.' "$entries")"; unresolved="$(jq '[.[]|select(.resolved|not)]|length' <<<"$ledger")"; regressions="$(jq '[.[]|select(.regression_fixture!=true)]|length' <<<"$ledger")"
matcher_after="$(jq -c '.matcher_after // .matcher_before // {}' "$INPUT")"
narrowed="$(jq -n --argjson before "$matcher_before" --argjson after "$matcher_after" '($after|tojson|length) >= ($before|tojson|length)')"
state="active"; [[ "$unresolved" -ge 2 ]] && state="demoted"; [[ "$unresolved" -ge 3 ]] && state="retired"
report="$(jq -n --arg macro_id "$macro_id" --arg state "$state" --argjson ledger "$ledger" --argjson unresolved "$unresolved" --argjson regressions "$regressions" --argjson narrowed "$narrowed" '{schema_version:"1.0",ok:true,macro_id:$macro_id,state:$state,entries:$ledger,summary:{counterexamples:($ledger|length),unresolved:$unresolved,counterexample_regressions:$regressions,automatic_safety_weakening:0},refinement:{matcher_change:(if $narrowed then "narrow_or_equal" else "rejected_broadened_matcher" end),evidence_requirements_added:true,policy_mutation:false},trusted_apply_allowed:false}')"
printf '%s\n' "$report" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"CEGIS \(.macro_id) state=\(.state) unresolved=\(.summary.unresolved)"' "$OUT"; fi
