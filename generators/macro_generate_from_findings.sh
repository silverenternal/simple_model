#!/usr/bin/env bash
set -euo pipefail

FINDINGS=""
OUT="generated/macros/candidates.json"
JSON_OUT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --findings) FINDINGS="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

mkdir -p "$(dirname "$OUT")"
if [[ -z "$FINDINGS" || ! -f "$FINDINGS" ]]; then
  FINDINGS="$(mktemp)"
  trap 'rm -f "$FINDINGS"' EXIT
  jq -n '{findings:[
    {kind:"boundary_drift", path:"src/a.ts", score_delta:0.18, risk:"medium"},
    {kind:"boundary_drift", path:"src/b.ts", score_delta:0.15, risk:"medium"},
    {kind:"dynamic_route_gap", path:"src/routes.ts", score_delta:0.11, risk:"high"}
  ]}' > "$FINDINGS"
fi

report=$(jq -n --slurpfile findings "$FINDINGS" '
  ($findings[0].findings // $findings[0].candidates // []) as $findings
  | ($findings | group_by(.kind // "unknown") | map({
      id:("generated." + (.[0].kind // "unknown")),
      status:"review_only",
      source_kind:(.[0].kind // "unknown"),
      occurrences:length,
      paths:(map(.path)|unique|sort),
      expected_score_delta:(map(.score_delta // 0)|add),
      risk_class:(if any(.[]; (.risk // "") == "high") then "high" else "medium" end),
      preconditions:{confidence_floor:0.82, dynamic_evidence:"trusted_only"},
      write_set:(map(.path)|unique|sort),
      missing_evidence:["golden_fixtures","macro_preconditions","macro_drill","score_evidence"],
      apply_capable:false
    }) | sort_by(.id)) as $candidates
  | {
      schema_version:"1.0", ok:true,
      summary:{findings:($findings|length), candidates:($candidates|length), apply_capable:0},
      candidates:$candidates,
      policy:{generated_candidates_review_only:true}
    }')

printf '%s\n' "$report" > "$OUT"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Generated macro candidates=" + (.summary.candidates|tostring)' <<<"$report"; fi
